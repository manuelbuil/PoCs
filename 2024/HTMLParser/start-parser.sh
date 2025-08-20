#!/bin/bash

# Activate the Python virtual environment
source /home/manuel/go/src/github.com/manuelbuil/PoCs/2024/HTMLParser/sego_env/bin/activate

# Run your Python script | sudo journalctl -t MyPythonScript to check the logs
python /home/manuel/go/src/github.com/manuelbuil/PoCs/2024/HTMLParser/miparser.py 2>&1 | logger -t MyPythonScript

# Deactivate the virtual environment (optional)
deactivate
