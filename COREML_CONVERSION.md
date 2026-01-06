# CoreML Model Conversion for VibrantFrog Collab

## Overview

This guide explains how to convert the `all-MiniLM-L6-v2` sentence embedding model to CoreML format for use in the VibrantFrog Collab iOS/Mac app.

## Why Convert to CoreML?

- **On-device inference**: Generate embeddings without API calls
- **Offline capability**: Works without internet connection
- **Privacy**: Search queries never leave the device
- **Speed**: Fast inference on Neural Engine (~5-10ms)
- **No cost**: Zero API costs for search

## Prerequisites

```bash
pip install coremltools sentence-transformers torch
```

## Conversion Steps

### Option 1: Run the Conversion Script (Recommended)

```bash
cd /Users/tpiazza/git/VibrantFrogMCP
python convert_to_coreml.py
```

**Output:**
```
✅ CoreML model saved to: SentenceEmbedding.mlpackage
📦 Model size: 90.2 MB
```

### Option 2: Manual Conversion (Advanced)

If the automatic script has issues, you can follow the manual steps in `SWIFT_INTEGRATION.md`.

## What Gets Created

```
VibrantFrogMCP/
└── SentenceEmbedding.mlpackage/     ← CoreML model (~90 MB)
    ├── Data/
    │   └── ...model weights...
    └── Manifest.json
```

## Next Steps

1. **Copy to Xcode Project:**
   ```bash
   # Copy the .mlpackage to your Xcode project
   cp -r SentenceEmbedding.mlpackage /Users/tpiazza/git/AuthorAICollab/AuthorAICollab/Models/
   ```

2. **Add to Xcode:**
   - Drag `SentenceEmbedding.mlpackage` into Xcode
   - Ensure it's added to your app target
   - Xcode will auto-generate a Swift class

3. **Download Vocabulary:**
   The model also needs a vocabulary file for tokenization. You can:

   **Option A:** Extract from the model (recommended):
   ```python
   from sentence_transformers import SentenceTransformer
   model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2')

   # Save vocabulary
   model.tokenizer.save_vocabulary('/Users/tpiazza/git/AuthorAICollab/AuthorAICollab/Resources/')
   ```

   **Option B:** Download directly:
   ```bash
   curl -o vocab.txt https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/main/vocab.txt
   ```

4. **Bundle in App:**
   Add `vocab.txt` to your Xcode project as a resource file.

## Verification

Test the CoreML model before integrating:

```python
# Test the converted model
python -c "
import coremltools as ct
model = ct.models.MLModel('SentenceEmbedding.mlpackage')
print('Model loaded successfully!')
print(f'Inputs: {model.get_spec().description.input}')
print(f'Outputs: {model.get_spec().description.output}')
"
```

## Integration in Swift

See `SWIFT_INTEGRATION.md` for complete Swift integration code.

Quick example:

```swift
import CoreML

class EmbeddingGenerator {
    private let model: SentenceEmbedding

    init() throws {
        self.model = try SentenceEmbedding(configuration: MLModelConfiguration())
    }

    func encode(_ text: String) throws -> [Float] {
        // Tokenize, run model, return 384-dimensional vector
        // (Full implementation in SWIFT_INTEGRATION.md)
    }
}
```

## Troubleshooting

### Error: "No module named 'coremltools'"
```bash
pip install --upgrade coremltools
```

### Error: "No module named 'sentence_transformers'"
```bash
pip install sentence-transformers torch
```

### Model file too large for git
The `SentenceEmbedding.mlpackage` is ~90 MB. Consider:
- Adding to `.gitignore`
- Using Git LFS
- Downloading separately in CI/CD

### Conversion fails with memory error
```bash
# Use fewer resources
export PYTORCH_CUDA_ALLOC_CONF=max_split_size_mb:128
python convert_to_coreml.py
```

## Model Details

- **Name:** all-MiniLM-L6-v2
- **Source:** sentence-transformers/all-MiniLM-L6-v2
- **Architecture:** BERT-based transformer
- **Embedding dimensions:** 384
- **Max sequence length:** 128 tokens
- **License:** Apache 2.0

## Performance

- **Model size:** ~90 MB
- **Inference time:** 5-10ms on iPhone 13+
- **Memory usage:** ~50 MB
- **Batch size:** 1 (real-time search)

## Notes

- The model is quantized for smaller size (can be disabled if needed)
- Uses ML Program format for best performance on iOS 15+
- Compatible with Neural Engine for hardware acceleration

## Resources

- [CoreML Tools Documentation](https://coremltools.readme.io/)
- [Sentence Transformers](https://www.sbert.net/)
- [HuggingFace Model Card](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2)
