# Fixing Slow Indexing Performance

## Problem Diagnosed
LLaVA 13B is taking **6.6 minutes per photo** on your system.

## Solution 1: Switch to llava:7b (RECOMMENDED)

### Download the smaller model:
```bash
ollama pull llava:7b
```

### Update both scripts to use it:
The scripts need to change from `llava:13b` to `llava:7b`

**Expected improvement:**
- Current: 6.6 minutes per photo
- With llava:7b: 2-3 minutes per photo (2-3x faster)
- Quality: Still very good, slightly less detailed descriptions

---

## Solution 2: Use llava:13b-q4 (Quantized version)

### Download quantized model:
```bash
ollama pull llava:13b-q4
```

Lower precision, faster inference, similar quality.

---

## Solution 3: Hardware Acceleration Check

Your Mac may not be using GPU acceleration properly.

### Check if Metal (GPU) is being used:
```bash
# While LLaVA is running, check activity:
top -pid $(pgrep ollama)
```

Look for high CPU usage = not using GPU properly.

### Ensure Ollama is using GPU:
Reinstall Ollama from https://ollama.ai - latest version has better Metal support.

---

## Comparison Table

| Model | Size | Speed | Quality | Recommended |
|-------|------|-------|---------|-------------|
| llava:7b | 4.5GB | 2-3 min/photo | Good | ✅ Yes |
| llava:13b-q4 | 6GB | 3-4 min/photo | Very Good | ⚠️ Try if 7b not detailed enough |
| llava:13b | 8GB | 6-7 min/photo | Excellent | ❌ Too slow for your system |

---

## How to Switch Models

### Step 1: Download new model
```bash
ollama pull llava:7b
```

### Step 2: Update index_photos.py

Change line 58 from:
```python
model='llava:13b',
```
to:
```python
model='llava:7b',
```

### Step 3: Update vibrant_frog_mcp.py

Change line 78 from:
```python
model='llava:13b',
```
to:
```python
model='llava:7b',
```

### Step 4: Test performance
```bash
python test_ollama.py path/to/test/image.jpg
```

Should now take 2-3 minutes instead of 6-7 minutes.
