package com.abbeyhill.yf2;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.os.Process;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.Locale;
import java.util.Random;
import java.util.concurrent.ConcurrentLinkedQueue;

public final class AudioEngine {
    public static final int SAMPLE_RATE = 48000;
    public static final int STEPS = 16;
    public static final int LANES = 8;
    public static final String[] ROLE_NAMES = {"KICK","SNARE","CLAP","C.HAT","O.HAT","TOM","ACID","BREAK"};
    public static final String[] BANK_NAMES = {"909","707","AMEN","303"};

    private final boolean[][] pattern = new boolean[LANES][STEPS];
    private final int[] padBanks = new int[LANES];
    private final ConcurrentLinkedQueue<Trigger> pending = new ConcurrentLinkedQueue<>();
    private final Random rng = new Random();
    private final Object stateLock = new Object();

    private volatile boolean audioRunning;
    private volatile boolean playing;
    private volatile boolean monoCheck;
    private volatile int bpm = 132;
    private volatile int currentStep = -1;
    private volatile float meterL;
    private volatile float meterR;
    private volatile float drive = 0.24f;
    private volatile float filter = 0.78f;
    private volatile float delay = 0.18f;
    private volatile float space = 0.12f;
    private volatile int selectedBank = 0;
    private Thread audioThread;
    private AudioTrack audioTrack;

    public AudioEngine() {
        for (int i = 0; i < LANES; i++) padBanks[i] = 0;
        int[] kicks = {0,4,8,12};
        for (int s : kicks) pattern[0][s] = true;
        pattern[1][4] = pattern[1][12] = true;
        for (int s = 2; s < 16; s += 4) pattern[2][s] = true;
        for (int s = 0; s < 16; s += 2) pattern[3][s] = true;
        pattern[4][6] = pattern[4][14] = true;
        pattern[6][0] = pattern[6][3] = pattern[6][7] = pattern[6][10] = pattern[6][14] = true;
    }

    public void startAudio() {
        if (audioRunning) return;
        int min = AudioTrack.getMinBufferSize(SAMPLE_RATE,
                AudioFormat.CHANNEL_OUT_STEREO, AudioFormat.ENCODING_PCM_16BIT);
        int frames = Math.max(512, min / 4);
        int bytes = frames * 4;
        audioTrack = new AudioTrack.Builder()
                .setAudioAttributes(new AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_GAME)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build())
                .setAudioFormat(new AudioFormat.Builder()
                        .setSampleRate(SAMPLE_RATE)
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_STEREO)
                        .build())
                .setBufferSizeInBytes(bytes * 2)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build();
        audioRunning = true;
        audioTrack.play();
        audioThread = new Thread(() -> renderLoop(frames), "YF2-Audio");
        audioThread.start();
    }

    public void stopAudio() {
        audioRunning = false;
        if (audioThread != null) {
            try { audioThread.join(700); } catch (InterruptedException ignored) { }
            audioThread = null;
        }
        if (audioTrack != null) {
            try { audioTrack.pause(); audioTrack.flush(); audioTrack.release(); } catch (Exception ignored) { }
            audioTrack = null;
        }
        meterL = meterR = 0f;
    }

    public void togglePlay() { playing = !playing; }
    public boolean isPlaying() { return playing; }
    public int getCurrentStep() { return currentStep; }
    public int getBpm() { return bpm; }
    public void adjustBpm(int delta) { bpm = Math.max(60, Math.min(190, bpm + delta)); }
    public float getMeterL() { return meterL; }
    public float getMeterR() { return meterR; }
    public boolean isMonoCheck() { return monoCheck; }
    public void toggleMonoCheck() { monoCheck = !monoCheck; }
    public int getSelectedBank() { return selectedBank; }
    public String getSelectedBankName() { return BANK_NAMES[selectedBank]; }
    public int getPadBank(int lane) { return padBanks[lane]; }

    public void cycleBank() {
        selectedBank = (selectedBank + 1) % BANK_NAMES.length;
        synchronized (stateLock) {
            for (int i = 0; i < LANES; i++) padBanks[i] = selectedBank;
        }
    }

    public void mixBanks() {
        synchronized (stateLock) {
            for (int lane = 0; lane < LANES; lane++) {
                int x = rng.nextInt(100);
                int bank = x < 40 ? 0 : x < 70 ? 1 : x < 85 ? 2 : 3;
                if (lane == 6 && rng.nextFloat() < 0.72f) bank = 3;
                if (lane == 7 && rng.nextFloat() < 0.72f) bank = 2;
                padBanks[lane] = bank;
            }
        }
    }

    public void shufflePattern() {
        float[] density = {0.26f,0.13f,0.10f,0.36f,0.10f,0.10f,0.22f,0.08f};
        synchronized (stateLock) {
            for (int l = 0; l < LANES; l++) {
                for (int s = 0; s < STEPS; s++) pattern[l][s] = rng.nextFloat() < density[l];
            }
            pattern[0][0] = true;
        }
    }

    public boolean getStep(int lane, int step) {
        synchronized (stateLock) { return pattern[lane][step]; }
    }

    public void toggleStep(int lane, int step) {
        synchronized (stateLock) { pattern[lane][step] = !pattern[lane][step]; }
    }

    public void clearPattern() {
        synchronized (stateLock) {
            for (int l = 0; l < LANES; l++) for (int s = 0; s < STEPS; s++) pattern[l][s] = false;
        }
    }

    public void triggerPad(int lane) {
        pending.add(new Trigger(lane, padBanks[lane], 1f));
    }

    public float getFx(int which) {
        return switch (which) { case 0 -> drive; case 1 -> filter; case 2 -> delay; default -> space; };
    }

    public void setFx(int which, float value) {
        value = Math.max(0f, Math.min(1f, value));
        switch (which) { case 0 -> drive = value; case 1 -> filter = value; case 2 -> delay = value; default -> space = value; }
    }

    public String getFxText(int which) {
        String n = switch (which) { case 0 -> "DRIVE"; case 1 -> "FILTER"; case 2 -> "DELAY"; default -> "SPACE"; };
        return String.format(Locale.US, "%s %02d", n, Math.round(getFx(which) * 99f));
    }

    private void renderLoop(int framesPerBuffer) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_AUDIO);
        short[] out = new short[framesPerBuffer * 2];
        ArrayList<Voice> voices = new ArrayList<>(32);
        int delayFrames = SAMPLE_RATE * 3 / 16;
        float[] delayL = new float[delayFrames];
        float[] delayR = new float[delayFrames];
        int delayPos = 0;
        float lpL = 0f, lpR = 0f;
        long sampleCounter = 0;
        long nextStepSample = 0;
        int step = -1;

        while (audioRunning) {
            float peakL = 0f, peakR = 0f;
            for (int f = 0; f < framesPerBuffer; f++, sampleCounter++) {
                long samplesPerStep = Math.max(1, Math.round((SAMPLE_RATE * 60.0) / bpm / 4.0));
                if (playing && sampleCounter >= nextStepSample) {
                    step = (step + 1) & 15;
                    currentStep = step;
                    nextStepSample = sampleCounter + samplesPerStep;
                    synchronized (stateLock) {
                        for (int lane = 0; lane < LANES; lane++) {
                            if (pattern[lane][step]) voices.add(new Voice(lane, padBanks[lane], 0.92f, rng));
                        }
                    }
                } else if (!playing) {
                    nextStepSample = sampleCounter;
                    currentStep = -1;
                }

                Trigger t;
                while ((t = pending.poll()) != null) voices.add(new Voice(t.lane, t.bank, t.velocity, rng));

                float l = 0f, r = 0f;
                Iterator<Voice> it = voices.iterator();
                while (it.hasNext()) {
                    Voice v = it.next();
                    float mono = v.nextSample();
                    if (v.dead) { it.remove(); continue; }
                    l += mono * v.gainL;
                    r += mono * v.gainR;
                }

                float fc = 0.035f + filter * 0.42f;
                lpL += fc * (l - lpL);
                lpR += fc * (r - lpR);
                float dGain = 1.0f + drive * 5.5f;
                l = softClip(lpL * dGain) / (1f + drive * 0.55f);
                r = softClip(lpR * dGain) / (1f + drive * 0.55f);

                float dl = delayL[delayPos];
                float dr = delayR[delayPos];
                float wet = delay * 0.52f;
                float cross = space * 0.42f;
                delayL[delayPos] = l + dl * (delay * 0.46f) + dr * cross;
                delayR[delayPos] = r + dr * (delay * 0.46f) + dl * cross;
                delayPos++; if (delayPos >= delayFrames) delayPos = 0;
                l += dl * wet;
                r += dr * wet;

                if (monoCheck) {
                    float m = (l + r) * 0.5f;
                    l = r = m;
                }
                l = Math.max(-0.98f, Math.min(0.98f, l));
                r = Math.max(-0.98f, Math.min(0.98f, r));
                peakL = Math.max(peakL, Math.abs(l));
                peakR = Math.max(peakR, Math.abs(r));
                out[f * 2] = (short)(l * 32767f);
                out[f * 2 + 1] = (short)(r * 32767f);
            }
            meterL = Math.max(peakL, meterL * 0.83f);
            meterR = Math.max(peakR, meterR * 0.83f);
            AudioTrack track = audioTrack;
            if (track != null) track.write(out, 0, out.length, AudioTrack.WRITE_BLOCKING);
        }
    }

    private static float softClip(float x) {
        return x / (1f + Math.abs(x));
    }

    private record Trigger(int lane, int bank, float velocity) { }

    private static final class Voice {
        final int lane, bank;
        final float gainL, gainR;
        final Random rng;
        int age;
        boolean dead;
        double phase;
        double auxPhase;
        float lastNoise;

        Voice(int lane, int bank, float velocity, Random rng) {
            this.lane = lane; this.bank = bank; this.rng = rng;
            float pan = switch (lane) { case 2 -> -0.16f; case 3 -> 0.12f; case 4 -> 0.22f; case 5 -> -0.10f; case 7 -> 0.18f; default -> 0f; };
            double angle = (pan + 1.0) * Math.PI / 4.0;
            gainL = (float)Math.cos(angle) * velocity * 0.82f;
            gainR = (float)Math.sin(angle) * velocity * 0.82f;
        }

        float nextSample() {
            age++;
            float x;
            switch (lane) {
                case 0 -> x = kick();
                case 1 -> x = snare();
                case 2 -> x = clap();
                case 3 -> x = hat(false);
                case 4 -> x = hat(true);
                case 5 -> x = tom();
                case 6 -> x = acid();
                default -> x = breakVoice();
            }
            if (age > SAMPLE_RATE * 2) dead = true;
            return x;
        }

        private float kick() {
            float t = age / (float)SAMPLE_RATE;
            float base = bank == 1 ? 74f : bank == 2 ? 66f : bank == 3 ? 82f : 58f;
            float drop = bank == 0 ? 170f : 120f;
            float hz = base + drop * (float)Math.exp(-t * 35f);
            phase += hz / SAMPLE_RATE;
            float e = (float)Math.exp(-t * (bank == 0 ? 8.5f : 11.5f));
            if (e < 0.0009f) dead = true;
            float click = age < 90 ? (1f - age / 90f) * (rng.nextFloat() * 2f - 1f) * 0.18f : 0f;
            return ((float)Math.sin(phase * Math.PI * 2) * e * 1.15f) + click;
        }

        private float snare() {
            float t = age / (float)SAMPLE_RATE;
            float decay = bank == 1 ? 13f : 10f;
            float e = (float)Math.exp(-t * decay);
            phase += (bank == 1 ? 184f : 205f) / SAMPLE_RATE;
            float noise = rng.nextFloat() * 2f - 1f;
            lastNoise += 0.55f * (noise - lastNoise);
            if (e < 0.001f) dead = true;
            return (0.62f * lastNoise + 0.38f * (float)Math.sin(phase * Math.PI * 2)) * e;
        }

        private float clap() {
            float t = age / (float)SAMPLE_RATE;
            float burst = 0f;
            int q = age % 620;
            if (age < 2200 && q < 210) burst = 1f - q / 210f;
            float tail = (float)Math.exp(-t * 17f);
            if (tail < 0.001f) dead = true;
            float n = rng.nextFloat() * 2f - 1f;
            lastNoise = 0.78f * lastNoise + 0.22f * n;
            return (n - lastNoise) * (0.5f * burst + 0.42f * tail);
        }

        private float hat(boolean open) {
            float t = age / (float)SAMPLE_RATE;
            float e = (float)Math.exp(-t * (open ? 8f : 42f));
            float n = rng.nextFloat() * 2f - 1f;
            lastNoise = 0.90f * lastNoise + 0.10f * n;
            float hp = n - lastNoise;
            phase += (bank == 1 ? 7600f : 9200f) / SAMPLE_RATE;
            float metal = (float)Math.signum(Math.sin(phase * Math.PI * 2)) * 0.22f;
            if (e < 0.001f) dead = true;
            return (hp * 0.75f + metal) * e * 0.62f;
        }

        private float tom() {
            float t = age / (float)SAMPLE_RATE;
            float e = (float)Math.exp(-t * 10f);
            phase += (bank == 1 ? 136f : 112f) / SAMPLE_RATE;
            if (e < 0.001f) dead = true;
            return (float)Math.sin(phase * Math.PI * 2) * e * 0.82f;
        }

        private float acid() {
            float t = age / (float)SAMPLE_RATE;
            int note = bank == 3 ? 45 : 40;
            float hz = 440f * (float)Math.pow(2, (note - 69) / 12.0);
            phase += hz / SAMPLE_RATE;
            auxPhase += (hz * 2.01) / SAMPLE_RATE;
            float saw = (float)(2.0 * (phase - Math.floor(phase + 0.5)));
            float sq = Math.sin(auxPhase * Math.PI * 2) >= 0 ? 1f : -1f;
            float e = (float)Math.exp(-t * 5.2f);
            float wob = 0.72f + 0.28f * (float)Math.sin(t * 17.0);
            if (e < 0.001f) dead = true;
            return (saw * 0.68f + sq * 0.20f) * e * wob * 0.58f;
        }

        private float breakVoice() {
            float t = age / (float)SAMPLE_RATE;
            float e = (float)Math.exp(-t * 7.0f);
            int micro = (age / 900) & 7;
            float n = rng.nextFloat() * 2f - 1f;
            phase += (micro == 0 || micro == 4 ? 62f : 190f + micro * 23f) / SAMPLE_RATE;
            float tonal = (float)Math.sin(phase * Math.PI * 2);
            float gate = ((age / 420) % 4 == 0) ? 1f : 0.36f;
            if (e < 0.001f) dead = true;
            return (tonal * 0.42f + n * 0.34f) * e * gate;
        }
    }
}
