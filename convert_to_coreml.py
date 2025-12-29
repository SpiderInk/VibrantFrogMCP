#!/usr/bin/env python3
"""
Convert all-MiniLM-L6-v2 sentence transformer to CoreML
for use in VibrantFrog Collab iOS/Mac app

This allows the app to generate embeddings on-device without API calls.
"""

import torch
import coremltools as ct
from sentence_transformers import SentenceTransformer
import numpy as np
from pathlib import Path

def convert_sentence_transformer_to_coreml():
    """
    Convert the all-MiniLM-L6-v2 model to CoreML format
    """
    # Force CPU to avoid MPS issues
    import os
    os.environ['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'

    print("Loading sentence-transformers model...")
    model = SentenceTransformer('sentence-transformers/all-MiniLM-L6-v2', device='cpu')

    # Get the underlying transformer model
    transformer = model[0].auto_model
    transformer = transformer.cpu()  # Ensure it's on CPU
    tokenizer = model.tokenizer

    print("Model loaded successfully")
    print(f"Embedding dimension: {model.get_sentence_embedding_dimension()}")

    # Test the model first
    test_sentence = "This is a test sentence"
    test_embedding = model.encode(test_sentence)
    print(f"\nTest encoding:")
    print(f"Input: {test_sentence}")
    print(f"Output shape: {test_embedding.shape}")
    print(f"First 5 values: {test_embedding[:5]}")

    # Prepare for CoreML conversion
    # We need to trace the model with example inputs
    print("\nPreparing for CoreML conversion...")

    # Tokenize example input
    example_text = "example sentence for conversion"
    inputs = tokenizer(
        example_text,
        padding='max_length',
        max_length=128,  # Fixed length for CoreML
        truncation=True,
        return_tensors='pt'
    )

    # Create a traced model
    class EmbeddingModel(torch.nn.Module):
        def __init__(self, transformer):
            super().__init__()
            self.transformer = transformer

        def forward(self, input_ids, attention_mask):
            # Run through transformer
            outputs = self.transformer(
                input_ids=input_ids,
                attention_mask=attention_mask
            )

            # Mean pooling
            token_embeddings = outputs[0]
            input_mask_expanded = attention_mask.unsqueeze(-1).expand(token_embeddings.size()).float()
            sum_embeddings = torch.sum(token_embeddings * input_mask_expanded, 1)
            sum_mask = torch.clamp(input_mask_expanded.sum(1), min=1e-9)
            embeddings = sum_embeddings / sum_mask

            # Normalize
            embeddings = torch.nn.functional.normalize(embeddings, p=2, dim=1)

            return embeddings

    embedding_model = EmbeddingModel(transformer)
    embedding_model.eval()

    # Test the traced model
    with torch.no_grad():
        traced_output = embedding_model(inputs['input_ids'], inputs['attention_mask'])
        print(f"Traced model output shape: {traced_output.shape}")
        print(f"First 5 values: {traced_output[0][:5].numpy()}")

    # Trace the model
    print("\nTracing model...")
    traced_model = torch.jit.trace(
        embedding_model,
        (inputs['input_ids'], inputs['attention_mask'])
    )

    # Convert to CoreML
    print("Converting to CoreML...")

    # Define input types
    input_ids_input = ct.TensorType(
        name="input_ids",
        shape=(1, 128),  # batch_size=1, sequence_length=128
        dtype=np.int32
    )

    attention_mask_input = ct.TensorType(
        name="attention_mask",
        shape=(1, 128),
        dtype=np.int32
    )

    # Convert
    mlmodel = ct.convert(
        traced_model,
        inputs=[input_ids_input, attention_mask_input],
        minimum_deployment_target=ct.target.iOS15,
        convert_to="mlprogram"  # Use ML Program for better performance
    )

    # Add metadata
    mlmodel.author = "VibrantFrog"
    mlmodel.license = "Apache 2.0"
    mlmodel.short_description = "Sentence embeddings model for semantic photo search"
    mlmodel.version = "1.0.0"

    # Add input descriptions
    mlmodel.input_description["input_ids"] = "Tokenized input text (max 128 tokens)"
    mlmodel.input_description["attention_mask"] = "Attention mask for input tokens"

    # Add output description (get actual output name)
    output_name = list(mlmodel.get_spec().description.output)[0].name
    mlmodel.output_description[output_name] = "384-dimensional sentence embedding vector"

    # Save the model
    output_path = "SentenceEmbedding.mlpackage"
    mlmodel.save(output_path)

    print(f"\n✅ CoreML model saved to: {output_path}")
    print(f"📦 Model size: {sum(f.stat().st_size for f in Path(output_path).rglob('*') if f.is_file()) / 1024 / 1024:.1f} MB")

    # Test the CoreML model
    print("\nTesting CoreML model...")
    predictions = mlmodel.predict({
        'input_ids': inputs['input_ids'].numpy().astype(np.int32),
        'attention_mask': inputs['attention_mask'].numpy().astype(np.int32)
    })

    coreml_output = list(predictions.values())[0][0]  # Get first prediction
    print(f"CoreML output shape: {coreml_output.shape}")
    print(f"First 5 values: {coreml_output[:5]}")

    # Compare with original
    print("\nComparing outputs:")
    original = traced_output[0].numpy()
    print(f"Original: {original[:5]}")
    print(f"CoreML:   {coreml_output[:5]}")
    print(f"Difference: {np.abs(original - coreml_output).max():.6f}")

    if np.allclose(original, coreml_output, atol=1e-3):
        print("✅ Outputs match! Conversion successful.")
    else:
        print("⚠️  Outputs differ slightly (this is normal for model conversion)")

    print(f"\n📝 Next steps:")
    print(f"1. Copy {output_path} to your Xcode project")
    print(f"2. Add to 'Copy Bundle Resources' build phase")
    print(f"3. Use the Swift integration code provided")

    return output_path


if __name__ == "__main__":
    try:
        import coremltools
        import sentence_transformers
        print("All dependencies available!")
        print(f"coremltools version: {coremltools.__version__}")
        print(f"sentence-transformers version: {sentence_transformers.__version__}")
        print()

        convert_sentence_transformer_to_coreml()

    except ImportError as e:
        print(f"❌ Missing dependency: {e}")
        print("\nPlease install required packages:")
        print("  pip install coremltools sentence-transformers torch")
