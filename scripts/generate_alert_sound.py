import math
import struct
import wave
import os

SAMPLE_RATE = 44100
AMPLITUDE = 32767 * 0.85  # 85% of full 16-bit range for loud clarity without clipping

def generate_tone(freq, duration, decay_rate=8.0, harmonics=((1.0, 1.0), (2.0, 0.35), (3.0, 0.15))):
    """Generates audio samples for a rich harmonic marimba/bell chime note."""
    num_samples = int(SAMPLE_RATE * duration)
    samples = []
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        envelope = math.exp(-decay_rate * t)
        
        # Superposition of fundamental + overtones
        sample_val = 0.0
        for overtone, weight in harmonics:
            sample_val += math.sin(2.0 * math.pi * (freq * overtone) * t) * weight
        
        # Soft-knee limiting & envelope
        sample_val = sample_val * envelope * AMPLITUDE
        # Clamp to 16-bit signed int
        val = max(-32768, min(32767, int(sample_val)))
        samples.append(val)
    return samples

def generate_silence(duration):
    num_samples = int(SAMPLE_RATE * duration)
    return [0] * num_samples

def create_rapido_chime_pattern():
    """Builds one cycle of the iconic Rapido/Uber dispatch chime."""
    pattern = []
    
    # 4-note ascending high-priority arpeggio
    notes = [
        (880.0, 0.08, 12.0),   # A5
        (1174.66, 0.08, 12.0), # D6
        (1396.91, 0.09, 10.0), # F6
        (1760.00, 0.22, 6.0),  # A6 - resonant peak
    ]
    
    for freq, dur, decay in notes:
        pattern.extend(generate_tone(freq, dur, decay_rate=decay))
        pattern.extend(generate_silence(0.02))
        
    pattern.extend(generate_silence(0.08))
    
    # High-intensity twin ping
    # Dual chord: 1760 Hz + 2093 Hz (A6 + C7)
    dur = 0.35
    num_samples = int(SAMPLE_RATE * dur)
    for i in range(num_samples):
        t = i / SAMPLE_RATE
        env = math.exp(-7.0 * t)
        s1 = math.sin(2.0 * math.pi * 1760.0 * t) + 0.3 * math.sin(2.0 * math.pi * 3520.0 * t)
        s2 = math.sin(2.0 * math.pi * 2093.0 * t) + 0.3 * math.sin(2.0 * math.pi * 4186.0 * t)
        sample_val = (s1 * 0.5 + s2 * 0.5) * env * AMPLITUDE
        val = max(-32768, min(32767, int(sample_val)))
        pattern.append(val)
        
    # Inter-burst pause (0.45s)
    pattern.extend(generate_silence(0.45))
    return pattern

def build_full_alert_sound():
    one_burst = create_rapido_chime_pattern()
    # Repeat burst 4 times (~4.8 seconds total duration)
    full_samples = one_burst * 4
    return full_samples

def write_wav(filename, samples):
    with wave.open(filename, 'w') as wav_file:
        # Stereo, 2 bytes per sample, 44100 Hz
        wav_file.setnchannels(2)
        wav_file.setsampwidth(2)
        wav_file.setframerate(SAMPLE_RATE)
        
        frames = bytearray()
        for s in samples:
            # Write both Left and Right channels
            packed = struct.pack('<h', s)
            frames.extend(packed) # Left
            frames.extend(packed) # Right
            
        wav_file.writeframes(frames)
    print(f"Generated {filename} ({len(samples)/SAMPLE_RATE:.2f}s, {len(frames)} bytes)")

if __name__ == '__main__':
    samples = build_full_alert_sound()
    
    raw_path = "/home/hp/Applications/RaftarGadi/RaftarGadi-DriverApp/android/app/src/main/res/raw/order_alert.wav"
    asset_path = "/home/hp/Applications/RaftarGadi/RaftarGadi-DriverApp/assets/sounds/order_alert.wav"
    
    write_wav(raw_path, samples)
    write_wav(asset_path, samples)
