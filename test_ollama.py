#!/usr/bin/env python3
"""
Quick test to diagnose Ollama/LLaVA performance issues
"""
import time
import ollama
import sys

def test_ollama_text():
    """Test basic Ollama text generation"""
    print("Testing Ollama text generation...")
    start = time.time()

    try:
        response = ollama.chat(
            model='llama2',  # or any text model you have
            messages=[{
                'role': 'user',
                'content': 'Say hello in one sentence.'
            }]
        )
        elapsed = time.time() - start
        print(f"✅ Text generation works: {elapsed:.2f}s")
        print(f"Response: {response['message']['content'][:100]}")
        return True
    except Exception as e:
        print(f"❌ Text generation failed: {e}")
        return False

def test_ollama_vision():
    """Test LLaVA vision model with a simple prompt"""
    if len(sys.argv) < 2:
        print("❌ Please provide an image path:")
        print("   python test_ollama.py /path/to/test/image.jpg")
        return False

    image_path = sys.argv[1]
    print(f"\nTesting LLaVA vision with: {image_path}")
    print("This should take 5-30 seconds with GPU, 2-5 minutes with CPU...")

    start = time.time()

    try:
        response = ollama.chat(
            model='llava:13b',
            messages=[{
                'role': 'user',
                'content': 'Describe this image in one sentence.',
                'images': [image_path]
            }]
        )
        elapsed = time.time() - start
        print(f"\n✅ Vision generation works: {elapsed:.2f}s")
        print(f"Response: {response['message']['content']}")

        if elapsed > 300:  # 5 minutes
            print("\n⚠️  WARNING: This is very slow! LLaVA took over 5 minutes.")
            print("   Recommended: Use llava:7b instead of llava:13b")
        elif elapsed > 60:
            print("\n⚠️  Slower than expected. Consider using llava:7b for better performance.")
        else:
            print("\n✅ Performance is good!")

        return True
    except Exception as e:
        print(f"❌ Vision generation failed: {e}")
        import traceback
        traceback.print_exc()
        return False

def check_ollama_status():
    """Check if Ollama is running and list available models"""
    print("Checking Ollama status...")
    try:
        models = ollama.list()
        print(f"✅ Ollama is running")
        print(f"\nAvailable models:")
        if 'models' in models:
            for model in models['models']:
                name = model.get('name', 'unknown')
                size = model.get('size', 0) / 1e9
                print(f"  - {name} ({size:.1f}GB)")
        else:
            print(f"  Models data: {models}")
        return True
    except Exception as e:
        print(f"❌ Cannot connect to Ollama: {e}")
        print("   Make sure Ollama is running: `ollama serve`")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("="*60)
    print("Ollama/LLaVA Performance Test")
    print("="*60)

    # Step 1: Check Ollama is running
    if not check_ollama_status():
        sys.exit(1)

    print("\n" + "="*60)

    # Step 2: Test text generation (skip if no text model)
    # test_ollama_text()

    print("\n" + "="*60)

    # Step 3: Test vision
    test_ollama_vision()
