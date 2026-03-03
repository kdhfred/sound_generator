package io.github.mertguner.sound_generator.handlers;

import java.util.List;

import io.flutter.plugin.common.EventChannel;

public class getOneCycleDataHandler implements EventChannel.StreamHandler {
    public static final String NATIVE_CHANNEL_EVENT = "io.github.mertguner.sound_generator/onOneCycleDataHandler";
    private volatile static getOneCycleDataHandler mEventManager;
    private volatile EventChannel.EventSink eventSink;

    public getOneCycleDataHandler() {
        mEventManager = this;
    }

    @Override
    public void onListen(Object o, EventChannel.EventSink eventSink) {
        this.eventSink = eventSink;
    }

    public static void setData(List<Integer> value) {
        // Capture local references to avoid TOCTOU race
        getOneCycleDataHandler manager = mEventManager;
        if (manager != null) {
            EventChannel.EventSink sink = manager.eventSink;
            if (sink != null) {
                sink.success(value);
            }
        }
    }

    @Override
    public void onCancel(Object o) {
        this.eventSink = null;
    }
}
