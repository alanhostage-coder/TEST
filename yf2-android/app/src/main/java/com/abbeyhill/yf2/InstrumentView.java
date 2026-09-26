package com.abbeyhill.yf2;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.SystemClock;
import android.view.MotionEvent;
import android.view.View;

import java.util.Locale;

public final class InstrumentView extends View {
    private static final int BG = Color.rgb(233,227,211);
    private static final int INK = Color.rgb(23,23,23);
    private static final int ORANGE = Color.rgb(240,90,50);
    private static final int YELLOW = Color.rgb(239,196,73);
    private static final int BLUE = Color.rgb(99,151,169);
    private static final int GREEN = Color.rgb(123,145,109);
    private static final int GREY = Color.rgb(190,184,169);
    private final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
    private final AudioEngine engine;
    private boolean uiRunning;
    private int dragFx = -1;
    private float dragStartY;
    private float dragStartValue;
    private long lastTapTime;

    public InstrumentView(Context context, AudioEngine engine) {
        super(context);
        this.engine = engine;
        setBackgroundColor(BG);
        p.setTypeface(android.graphics.Typeface.create("sans", android.graphics.Typeface.BOLD));
    }

    public void setRunningUi(boolean running) {
        uiRunning = running;
        if (running) invalidate();
    }

    @Override protected void onDraw(Canvas c) {
        super.onDraw(c);
        final float w = getWidth(), h = getHeight();
        float m = w * 0.04f;
        c.drawColor(BG);

        p.setColor(INK); p.setStyle(Paint.Style.FILL);
        c.drawRect(0,0,w,h*0.075f,p);
        text(c,"YF/2",m,h*0.051f,w*0.070f,BG,Paint.Align.LEFT);
        text(c,"STEREO SAMPLER / 48K",w-m,h*0.047f,w*0.027f,BG,Paint.Align.RIGHT);

        float y = h*0.095f;
        float bh = h*0.055f;
        button(c,new RectF(m,y,m+w*0.19f,y+bh),engine.isPlaying()?"STOP":"PLAY",engine.isPlaying()?ORANGE:INK,BG);
        button(c,new RectF(m+w*0.205f,y,m+w*0.39f,y+bh),"BANK "+engine.getSelectedBankName(),BLUE,BG);
        button(c,new RectF(m+w*0.405f,y,m+w*0.575f,y+bh),"MIX",YELLOW,INK);
        button(c,new RectF(m+w*0.59f,y,m+w*0.76f,y+bh),"SHUFFLE",GREEN,BG);
        button(c,new RectF(m+w*0.775f,y,w-m,y+bh),engine.isMonoCheck()?"MONO":"STEREO",engine.isMonoCheck()?ORANGE:INK,BG);

        float meterY = y+bh+h*0.018f;
        text(c,String.format(Locale.US,"%03d BPM",engine.getBpm()),m,meterY+h*0.022f,w*0.034f,INK,Paint.Align.LEFT);
        float meterX = w*0.38f, meterW = w*0.57f, meterH = h*0.013f;
        meter(c,meterX,meterY,meterW,meterH,engine.getMeterL(),"L");
        meter(c,meterX,meterY+meterH+h*0.006f,meterW,meterH,engine.getMeterR(),"R");

        float padsTop = h*0.205f;
        float padGap = w*0.018f;
        float padW = (w - 2*m - 3*padGap) / 4f;
        float padH = h*0.087f;
        int[] ac = {ORANGE,BLUE,YELLOW,GREEN,BLUE,GREEN,ORANGE,YELLOW};
        for (int i=0;i<8;i++) {
            int row=i/4,col=i%4;
            float x=m+col*(padW+padGap), py=padsTop+row*(padH+padGap);
            RectF r=new RectF(x,py,x+padW,py+padH);
            p.setStyle(Paint.Style.FILL); p.setColor(i==6?INK:ac[i]); c.drawRoundRect(r,7,7,p);
            text(c,AudioEngine.ROLE_NAMES[i],x+padW*0.08f,py+padH*0.43f,w*0.030f,i==6?BG:INK,Paint.Align.LEFT);
            text(c,AudioEngine.BANK_NAMES[engine.getPadBank(i)],x+padW*0.08f,py+padH*0.75f,w*0.022f,i==6?GREY:INK,Paint.Align.LEFT);
        }

        float gridTop = h*0.405f;
        float rowH = h*0.039f;
        float labelW = w*0.13f;
        float gx = m+labelW;
        float stepGap = w*0.004f;
        float sw = (w-m-gx - 15*stepGap) / 16f;
        for (int l=0;l<8;l++) {
            float gy=gridTop+l*rowH;
            text(c,String.format(Locale.US,"%02d",l+1),m,gy+rowH*0.65f,w*0.022f,INK,Paint.Align.LEFT);
            for(int s=0;s<16;s++) {
                RectF r=new RectF(gx+s*(sw+stepGap),gy,gx+s*(sw+stepGap)+sw,gy+rowH*0.72f);
                boolean on=engine.getStep(l,s);
                p.setStyle(Paint.Style.FILL);
                int color=on? (s==engine.getCurrentStep()?ORANGE:INK) : ((s%4==0)?GREY:Color.rgb(211,205,190));
                p.setColor(color); c.drawRoundRect(r,3,3,p);
                if (s==engine.getCurrentStep()) {p.setStyle(Paint.Style.STROKE);p.setStrokeWidth(2);p.setColor(ORANGE);c.drawRoundRect(r,3,3,p);}
            }
        }

        float fxTop = h*0.755f;
        text(c,"MACRO FX",m,fxTop,w*0.026f,INK,Paint.Align.LEFT);
        text(c,"DRAG UP / DOWN",w-m,fxTop,w*0.020f,INK,Paint.Align.RIGHT);
        float cy=h*0.845f;
        float radius=w*0.085f;
        for(int i=0;i<4;i++) {
            float cx=m+radius+(i*(w-2*m-2*radius)/3f);
            knob(c,cx,cy,radius,engine.getFx(i),i);
            text(c,engine.getFxText(i),cx,cy+radius+h*0.035f,w*0.022f,INK,Paint.Align.CENTER);
        }

        text(c,"CLEAN-ROOM BUILD • NO ORIGINAL YELLOFIER AUDIO INCLUDED",w*0.5f,h*0.985f,w*0.017f,INK,Paint.Align.CENTER);
        if (uiRunning) postInvalidateDelayed(33);
    }

    private void meter(Canvas c,float x,float y,float w,float h,float level,String label){
        text(c,label,x-w*0.035f,y+h*0.90f,getWidth()*0.019f,INK,Paint.Align.RIGHT);
        p.setStyle(Paint.Style.FILL);p.setColor(INK);c.drawRoundRect(new RectF(x,y,x+w,y+h),3,3,p);
        float fill=Math.min(1f,level);
        p.setColor(fill>0.86f?ORANGE:GREEN);c.drawRoundRect(new RectF(x,y,x+w*fill,y+h),3,3,p);
    }

    private void button(Canvas c,RectF r,String label,int fill,int tc){
        p.setStyle(Paint.Style.FILL);p.setColor(fill);c.drawRoundRect(r,6,6,p);
        text(c,label,r.centerX(),r.centerY()+getWidth()*0.010f,getWidth()*0.022f,tc,Paint.Align.CENTER);
    }

    private void knob(Canvas c,float cx,float cy,float radius,float value,int idx){
        p.setStyle(Paint.Style.FILL);p.setColor(INK);c.drawCircle(cx,cy,radius,p);
        p.setColor(BG);c.drawCircle(cx,cy,radius*0.78f,p);
        float a=(float)Math.toRadians(135+270*value);
        float x2=cx+(float)Math.cos(a)*radius*0.62f;
        float y2=cy+(float)Math.sin(a)*radius*0.62f;
        p.setColor(idx==0?ORANGE:idx==1?GREEN:idx==2?BLUE:YELLOW);p.setStrokeWidth(radius*0.12f);p.setStrokeCap(Paint.Cap.ROUND);
        c.drawLine(cx,cy,x2,y2,p); p.setStrokeCap(Paint.Cap.BUTT);
    }

    private void text(Canvas c,String s,float x,float y,float size,int color,Paint.Align align){
        p.setStyle(Paint.Style.FILL);p.setTextSize(size);p.setTextAlign(align);p.setColor(color);c.drawText(s,x,y,p);
    }

    @Override public boolean onTouchEvent(MotionEvent e) {
        float x=e.getX(), y=e.getY();
        float w=getWidth(), h=getHeight(), m=w*0.04f;
        if(e.getAction()==MotionEvent.ACTION_DOWN){
            float by=h*0.095f,bh=h*0.055f;
            if(y>=by&&y<=by+bh){
                if(x<m+w*0.19f) engine.togglePlay();
                else if(x<m+w*0.39f) engine.cycleBank();
                else if(x<m+w*0.575f) engine.mixBanks();
                else if(x<m+w*0.76f) engine.shufflePattern();
                else engine.toggleMonoCheck();
                invalidate(); return true;
            }
            if(y>h*0.15f&&y<h*0.20f&&x<w*0.33f){ engine.adjustBpm(x<w*0.16f?-1:1); invalidate(); return true; }

            float padsTop=h*0.205f,padGap=w*0.018f,padW=(w-2*m-3*padGap)/4f,padH=h*0.087f;
            if(y>=padsTop&&y<=padsTop+2*(padH+padGap)){
                int row=(int)((y-padsTop)/(padH+padGap));
                int col=(int)((x-m)/(padW+padGap));
                if(row>=0&&row<2&&col>=0&&col<4){int lane=row*4+col;engine.triggerPad(lane);performClick();invalidate();return true;}
            }

            float gridTop=h*0.405f,rowH=h*0.039f,labelW=w*0.13f,gx=m+labelW,stepGap=w*0.004f,sw=(w-m-gx-15*stepGap)/16f;
            if(y>=gridTop&&y<gridTop+8*rowH&&x>=gx){
                int lane=(int)((y-gridTop)/rowH);int step=(int)((x-gx)/(sw+stepGap));
                if(lane>=0&&lane<8&&step>=0&&step<16){engine.toggleStep(lane,step);invalidate();return true;}
            }

            float cy=h*0.845f,radius=w*0.10f;
            for(int i=0;i<4;i++){
                float cx=m+w*0.085f+(i*(w-2*m-2*w*0.085f)/3f);
                float dx=x-cx,dy=y-cy;
                if(dx*dx+dy*dy<radius*radius){dragFx=i;dragStartY=y;dragStartValue=engine.getFx(i);return true;}
            }
            if(y>h*0.70f&&x<w*0.25f){long now=SystemClock.uptimeMillis();if(now-lastTapTime<360)engine.clearPattern();lastTapTime=now;}
        } else if(e.getAction()==MotionEvent.ACTION_MOVE&&dragFx>=0){
            float v=dragStartValue+(dragStartY-y)/(h*0.24f);engine.setFx(dragFx,v);invalidate();return true;
        } else if(e.getAction()==MotionEvent.ACTION_UP||e.getAction()==MotionEvent.ACTION_CANCEL){dragFx=-1;return true;}
        return true;
    }

    @Override public boolean performClick(){ super.performClick(); return true; }
}
