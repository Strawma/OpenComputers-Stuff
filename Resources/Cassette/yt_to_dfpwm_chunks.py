import argparse
import subprocess
import sys
from pathlib import Path

# ---- Simple DFPWM encoder (Python) ----
class DFPWMEncoder:
  def __init__(self):
    self.level = 0
    self.response = 0
    self.lastbit = 0

  def encode(self, pcm_bytes):
    out = bytearray()
    level = self.level
    response = self.response
    lastbit = self.lastbit

    def clamp(v, lo, hi):
      return lo if v < lo else hi if v > hi else v

    for i in range(0, len(pcm_bytes), 2):
      s = int.from_bytes(pcm_bytes[i:i + 2], byteorder="little", signed=True)
      sample = s >> 8

      bit = 1 if sample >= level else 0
      target = 127 if bit else -128

      if bit == lastbit:
        response = clamp(response + 1, 0, 63)
      else:
        response = clamp(response - 1, 0, 63)
      level += ((target - level) * (response + 1)) >> 6

      byte_index = (i // 2) % 8
      if byte_index == 0:
        out.append(0)
      if bit:
        out[-1] |= (1 << byte_index)

      lastbit = bit

    self.level = level
    self.response = response
    self.lastbit = lastbit
    return bytes(out)

def run(cmd):
  print(">", " ".join(cmd))
  subprocess.check_call(cmd)

def download_audio(url, out_path):
  run(["yt-dlp", "-x", "--audio-format", "wav", "-o", str(out_path), url])

def convert_to_pcm_mono(wav_path, pcm_path, sample_rate, preprocess=True):
  """
    Convert audio to mono PCM with optional preprocessing for DFPWM.
    """
  # Build filter chain
  filters = []

  if preprocess:
    # High-pass: remove sub-bass rumble (<80Hz) that wastes bits
    filters.append("highpass=f=80")

    filters.append("afftdn=nf=-25")  # noise floor at -25dB

    # Low-pass: DFPWM struggles with high frequencies
    #    At 32768Hz, Nyquist is ~16kHz, but 8-10kHz sounds cleaner
    nyquist = sample_rate // 2
    lpf_freq = min(8000, nyquist - 1000)
    filters.append(f"lowpass=f={lpf_freq}")

    # Compressor: reduce dynamic range so quiet parts aren't lost in noise
    #    threshold=-20dB, ratio=4:1, attack=5ms, release=100ms
    filters.append("acompressor=threshold=-20dB:ratio=4:attack=5:release=100")

    # Normalize: maximize use of available range
    #    loudnorm does EBU R128 loudness normalization
    filters.append("loudnorm=I=-16:TP=-1.5:LRA=11")

    # Noise gate: silence very quiet parts to avoid encoding noise as signal
    #    threshold=-40dB, attack=10ms, release=100ms
    filters.append("agate=threshold=-40dB:attack=10:release=100")

  filter_str = ",".join(filters) if filters else "anull"

  cmd = [
    "ffmpeg", "-y",
    "-i", str(wav_path),
    "-af", filter_str,
    "-ac", "1",
    "-ar", str(sample_rate),
    "-f", "s16le",
    str(pcm_path)
  ]
  run(cmd)

def encode_dfpwm(pcm_path, dfpwm_path):
  enc = DFPWMEncoder()
  with open(pcm_path, "rb") as f_in, open(dfpwm_path, "wb") as f_out:
    while True:
      chunk = f_in.read(4096 * 2)
      if not chunk:
        break
      f_out.write(enc.encode(chunk))

def split_file(path, out_dir, chunk_bytes):
  out_dir.mkdir(parents=True, exist_ok=True)
  with open(path, "rb") as f:
    i = 1
    while True:
      data = f.read(chunk_bytes)
      if not data:
        break
      out_file = out_dir / f"{i}.dfpwm"
      with open(out_file, "wb") as out:
        out.write(data)
      i += 1

def main():
  ap = argparse.ArgumentParser(
      description="Download and convert audio to DFPWM for ComputerCraft"
  )
  ap.add_argument("url", help="YouTube URL")
  ap.add_argument("--out", default="out", help="Output directory")
  ap.add_argument("--chunk-seconds", type=int, default=10,
                  help="Seconds per chunk")
  ap.add_argument("--dfpwm1a", action="store_true",
                  help="Use DFPWM1a (48kHz) instead of old DFPWM (32768Hz)")
  ap.add_argument("--no-preprocess", action="store_true",
                  help="Disable audio preprocessing")
  args = ap.parse_args()

  out_dir = Path(args.out)
  tmp_wav = out_dir / "temp.wav"
  tmp_pcm = out_dir / "temp.pcm"
  full_dfpwm = out_dir / "full.dfpwm"

  out_dir.mkdir(parents=True, exist_ok=True)

  sample_rate = 48000 if args.dfpwm1a else 32768

  download_audio(args.url, tmp_wav)
  convert_to_pcm_mono(tmp_wav, tmp_pcm, sample_rate,
                      preprocess=not args.no_preprocess)
  encode_dfpwm(tmp_pcm, full_dfpwm)

  bytes_per_second = sample_rate // 8
  chunk_bytes = args.chunk_seconds * bytes_per_second
  split_file(full_dfpwm, out_dir, chunk_bytes)

  print("Done. Chunks in:", out_dir)

if __name__ == "__main__":
  sys.exit(main())