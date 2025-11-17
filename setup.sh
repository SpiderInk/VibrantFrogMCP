# Check what you have installed
python3 --version

# If you need to install Python 3.12 (via Homebrew)
brew install python@3.12

# Create a project directory
mkdir photo-search-mcp
cd photo-search-mcp

# Create virtual environment with Python 3.12
python3.12 -m venv venv

# Activate it
source venv/bin/activate

# Upgrade pip
pip install --upgrade pip

# Install all dependencies
pip install mcp chromadb pillow ollama sentence-transformers
pip install osxphotos
# Create a requirements.txt for reproducibility
pip freeze > requirements.txt

brew install ollama

# Verify installation
which ollama

# Start Ollama (it will run in the background automatically)
ollama serve