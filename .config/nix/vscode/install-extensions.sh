#!/bin/bash

# Check if the file exists
if [ ! -f vscode/extensions.txt ]; then
  echo "The file extensions.txt does not exist."
  exit 1
fi

echo "Begin VSCode extension installation"

# Read the file line by line and install each extension
while IFS= read -r line; do
  # Skip empty lines
  if [ -n "$line" ]; then
    OUTPUT=$(code --install-extension "$line")
    if [[ $OUTPUT =~ "was successfully installed" ]]; then
      echo "Installed extension: $line"
    fi
  fi
done < vscode/extensions.txt

echo "VSCode extension installation complete"