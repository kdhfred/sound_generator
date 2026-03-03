package io.github.mertguner.sound_generator;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;

import io.github.mertguner.sound_generator.handlers.isPlayingStreamHandler;
import io.github.mertguner.sound_generator.models.WaveTypes;

/**
 * Rewritten to mirror iOS SoundGeneratorPlugin.swift architecture:
 * - Lazy AudioTrack creation (deferred from init to first play)
 * - All audio work on a dedicated background thread (zero main-thread blocking)
 * - Inline waveform generation with per-sample volume ramping
 * - No unbounded thread creation
 */
public class SoundGenerator {

    private AudioTrack audioTrack;
    private Thread audioThread;
    private volatile boolean engineRunning = false;
    private volatile boolean isPlaying = false;
    private int sampleRate = 44100;
    private int bufferSamples;

    // Oscillator state (shared between main & audio thread via volatile)
    private volatile double frequency = 440.0;
    private volatile double targetVolume = 0.0;
    private volatile double pan = 0.0;
    private volatile int waveformIndex = 0; // 0=sine, 1=square, 2=triangle, 3=sawtooth

    // Audio-thread-local state
    private double currentVolume = 0.0;
    private double phase = 0.0;

    // User-set values (main thread only, read by audio thread via targetVolume)
    private double volume = 1.0;
    private double dB = -20.0;
    private boolean cleanStart = false;

    // ── Public API (called from main thread via method channel) ──────────

    /**
     * Stores sample rate and returns immediately.
     * AudioTrack creation is deferred to first startPlayback() call.
     */
    public boolean init(int sampleRate) {
        this.sampleRate = sampleRate;
        return true;
    }

    public void startPlayback() {
        ensureEngine();

        if (cleanStart) {
            phase = 0.0;
        }

        targetVolume = volume;
        isPlaying = true;
        isPlayingStreamHandler.change(true);
    }

    public void stopPlayback() {
        targetVolume = 0.0;
        isPlaying = false;
        isPlayingStreamHandler.change(false);
    }

    public void release() {
        stopPlayback();
        engineRunning = false;

        if (audioThread != null) {
            try {
                audioThread.join(2000);
            } catch (InterruptedException e) {
                audioThread.interrupt();
            }
            audioThread = null;
        }
    }

    public boolean isPlaying() { return isPlaying; }
    public int getSampleRate() { return sampleRate; }
    public float getFrequency() { return (float) frequency; }
    public float getVolume() { return (float) volume; }
    public float getDecibel() { return (float) dB; }

    public void setFrequency(float freq) {
        this.frequency = freq;
    }

    public void setBalance(float balance) {
        this.pan = Math.max(-1.0, Math.min(1.0, balance));
    }

    public void setVolume(float vol, boolean recalculateDecibel) {
        vol = Math.max(0f, Math.min(1f, vol));
        this.volume = vol;

        if (recalculateDecibel) {
            this.dB = (vol >= 0.000001f) ? 20.0 * Math.log10(vol) : -120.0;
        }

        if (isPlaying) {
            targetVolume = vol;
        }
    }

    public void setDecibel(float dB) {
        this.dB = dB;
        float linear = (float) Math.pow(10.0, dB / 20.0);
        setVolume(Math.max(0f, linear), false);
    }

    public void setWaveform(WaveTypes waveType) {
        switch (waveType) {
            case SINUSOIDAL: waveformIndex = 0; break;
            case SQUAREWAVE: waveformIndex = 1; break;
            case TRIANGLE:   waveformIndex = 2; break;
            case SAWTOOTH:   waveformIndex = 3; break;
            default:         waveformIndex = 0; break;
        }
    }

    public void setCleanStart(boolean cleanStart) {
        this.cleanStart = cleanStart;
    }

    public void setAutoUpdateOneCycleSample(boolean autoUpdate) { /* no-op */ }
    public void refreshOneCycleData() { /* no-op */ }

    // ── Engine lifecycle (lazy initialization) ──────────────────────────

    private synchronized void ensureEngine() {
        if (engineRunning) return;

        engineRunning = true;
        phase = 0.0;
        currentVolume = 0.0;

        audioThread = new Thread(this::audioLoop, "SoundGenerator-Audio");
        audioThread.setPriority(Thread.MAX_PRIORITY);
        audioThread.start();
    }

    /**
     * Runs entirely on the audio thread. Creates AudioTrack, then enters
     * the write loop. Mirrors iOS AVAudioSourceNode render callback.
     */
    private void audioLoop() {
        android.os.Process.setThreadPriority(
                android.os.Process.THREAD_PRIORITY_URGENT_AUDIO);

        try {
            int minBytes = AudioTrack.getMinBufferSize(
                    sampleRate,
                    AudioFormat.CHANNEL_OUT_MONO,
                    AudioFormat.ENCODING_PCM_16BIT);

            if (minBytes <= 0) {
                engineRunning = false;
                return;
            }

            bufferSamples = minBytes / 2; // 16-bit = 2 bytes per sample

            audioTrack = new AudioTrack(
                    new AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                            .build(),
                    new AudioFormat.Builder()
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .setSampleRate(sampleRate)
                            .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                            .build(),
                    minBytes,
                    AudioTrack.MODE_STREAM,
                    AudioManager.AUDIO_SESSION_ID_GENERATE);

            audioTrack.play();

            short[] buffer = new short[bufferSamples];
            // Volume ramp: full 0→1 in ~10 ms (matching iOS)
            final double rampSpeed = 1.0 / (sampleRate * 0.01);

            while (engineRunning) {
                final double freq = this.frequency;
                final double target = this.targetVolume;
                final int waveform = this.waveformIndex;
                final double phaseInc = freq / sampleRate;

                for (int i = 0; i < bufferSamples; i++) {
                    // Per-sample volume ramp to avoid clicks
                    if (currentVolume < target) {
                        currentVolume = Math.min(currentVolume + rampSpeed, target);
                    } else if (currentVolume > target) {
                        currentVolume = Math.max(currentVolume - rampSpeed, target);
                    }

                    double sample = generateSample(phase, waveform) * currentVolume;
                    buffer[i] = (short) (sample * Short.MAX_VALUE);

                    phase += phaseInc;
                    if (phase >= 1.0) phase -= 1.0;
                }

                audioTrack.write(buffer, 0, bufferSamples);
            }
        } catch (Exception e) {
            // AudioTrack creation or playback failed — silently disable
        } finally {
            if (audioTrack != null) {
                try { audioTrack.stop(); } catch (Exception ignored) {}
                try { audioTrack.release(); } catch (Exception ignored) {}
                audioTrack = null;
            }
            engineRunning = false;
        }
    }

    // ── Waveform generation (mirrors iOS generateSample) ────────────────

    private static double generateSample(double phase, int waveform) {
        switch (waveform) {
            case 0: // Sine
                return Math.sin(phase * 2.0 * Math.PI);
            case 1: // Square
                return phase < 0.5 ? 1.0 : -1.0;
            case 2: // Triangle
                if (phase < 0.25) return phase * 4.0;
                if (phase < 0.75) return 2.0 - phase * 4.0;
                return phase * 4.0 - 4.0;
            case 3: // Sawtooth
                return 2.0 * phase - 1.0;
            default:
                return Math.sin(phase * 2.0 * Math.PI);
        }
    }
}
