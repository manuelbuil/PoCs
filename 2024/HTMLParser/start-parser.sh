
#!/bin/bash

# Remove the mail so that it does not get huge
rm /var/spool/mail/manuel

# Activate the Python virtual environment
source /home/manuel/go/src/github.com/manuelbuil/PoCs/2024/HTMLParser/myenv/bin/activate

# Run your Python script
python /home/manuel/go/src/github.com/manuelbuil/PoCs/2024/HTMLParser/miparserWeb.py 

# Deactivate the virtual environment (optional)
deactivate
