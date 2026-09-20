package com.abbeyhill.yf2;

import android.app.Activity;
import android.os.Bundle;
import android.view.Window;
import android.view.WindowManager;

public final class MainActivity extends Activity {
    private AudioEngine engine;
    private InstrumentView instrumentView;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        requestWindowFeature(Window.FEATURE_NO_TITLE);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        engine = new AudioEngine();
        instrumentView = new InstrumentView(this, engine);
        setContentView(instrumentView);
    }

    @Override
    protected void onResume() {
        super.onResume();
        engine.startAudio();
        instrumentView.setRunningUi(true);
    }

    @Override
    protected void onPause() {
        instrumentView.setRunningUi(false);
        engine.stopAudio();
        super.onPause();
    }
}
