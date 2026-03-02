#!/bin/bash

# Activate the Python virtual environment
source /home/manuel/go/src/github.com/manuelbuil/PoCs/2024/HTMLParser/sego_env/bin/activate

# Run the persistent parser (visible browser, periodic checks)
# Log to terminal and syslog at the same time.
python /home/manuel/go/src/github.com/manuelbuil/PoCs/2024/HTMLParser/miparser_persistent.py 2>&1 | tee >(logger -t MyPythonScriptPersistent)

# Deactivate the virtual environment (optional)
deactivate
