package io.github.mertguner.sound_generator.handlers;

import io.flutter.plugin.common.EventChannel.EventSink;
import io.flutter.plugin.common.EventChannel.StreamHandler;

public class isPlayingStreamHandler implements StreamHandler {
    public static final String NATIVE_CHANNEL_EVENT = "io.github.mertguner.sound_generator/onChangeIsPlaying";
    private volatile static isPlayingStreamHandler mEventManager;
    private volatile EventSink eventSink;

    public isPlayingStreamHandler() {
        mEventManager = this;
    }

    @Override
    public void onListen(Object o, EventSink eventSink) {
        this.eventSink = eventSink;
    }

    public static void change(boolean value) {
        // Capture local references to avoid TOCTOU race
        isPlayingStreamHandler manager = mEventManager;
        if (manager != null) {
            EventSink sink = manager.eventSink;
            if (sink != null) {
                sink.success(Boolean.valueOf(value));
            }
        }
    }

    @Override
    public void onCancel(Object o) {
        this.eventSink = null;
    }
}
