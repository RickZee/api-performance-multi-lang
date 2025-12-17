#!/usr/bin/env python3
"""
Script to find and fix files with multiple trailing newlines.
Removes extra trailing newlines, keeping only one.
"""

import os
import sys
from pathlib import Path

# Directories to skip
SKIP_DIRS = {
    '.git', '.cursor', '.aws-sam', 'node_modules', '__pycache__', 
    '.gradle', 'target', 'build', 'dist', '.idea', '.vscode',
    'gradle', 'venv', 'env', '.venv'
}

# File extensions to process (None means all files)
# We'll process text files but skip binaries
TEXT_EXTENSIONS = {
    '.py', '.java', '.go', '.rs', '.js', '.ts', '.jsx', '.tsx',
    '.md', '.txt', '.sh', '.yml', '.yaml', '.json', '.toml',
    '.sql', '.proto', '.tf', '.hcl', '.properties', '.gradle',
    '.mod', '.sum', '.lock', '.dockerfile', '.gitignore',
    '.dockerignore', '.env', '.example', '.ini', '.cfg', '.conf',
    '.xml', '.html', '.css', '.scss', '.less', '.sass',
    '.c', '.cpp', '.h', '.hpp', '.cc', '.cxx',
    '.rb', '.php', '.swift', '.kt', '.scala', '.clj',
    '.lua', '.pl', '.pm', '.r', '.R', '.m', '.mm',
    '.sh', '.bash', '.zsh', '.fish', '.ps1', '.bat', '.cmd',
    '.makefile', '.mk', '.cmake', '.cmake.in',
    '.editorconfig', '.prettierrc', '.eslintrc', '.babelrc',
    '.gitattributes', '.gitmodules', '.gitkeep',
    # No extension files (like Dockerfile, Makefile)
    ''
}

def should_process_file(file_path):
    """Check if a file should be processed."""
    # Skip hidden files (except common config files)
    if file_path.name.startswith('.') and file_path.name not in {
        '.gitignore', '.dockerignore', '.editorconfig', '.gitattributes',
        '.prettierrc', '.eslintrc', '.babelrc', '.env', '.example'
    }:
        return False
    
    # Check if in skip directory
    for part in file_path.parts:
        if part in SKIP_DIRS:
            return False
    
    # Check extension
    ext = file_path.suffix.lower()
    if ext in TEXT_EXTENSIONS:
        return True
    
    # Check files without extension (like Dockerfile, Makefile)
    if ext == '' and file_path.name.lower() in {
        'dockerfile', 'makefile', 'rakefile', 'gemfile', 'procfile'
    }:
        return True
    
    return False

def fix_trailing_newlines(file_path):
    """Fix multiple trailing newlines in a file.
    
    Only fixes files with 2 or more trailing newlines.
    Preserves files with exactly 1 trailing newline.
    """
    try:
        # Read file in binary mode first to preserve encoding
        with open(file_path, 'rb') as f:
            content = f.read()
        
        # Try to decode as UTF-8
        try:
            text = content.decode('utf-8')
        except UnicodeDecodeError:
            # Skip binary files
            return False
        
        # Detect line ending style (Unix \n or Windows \r\n)
        has_crlf = b'\r\n' in content
        line_ending = '\r\n' if has_crlf else '\n'
        
        # Count trailing newlines
        # Handle both \n and \r\n patterns
        trailing_newlines = 0
        i = len(text) - 1
        while i >= 0:
            if text[i] == '\n':
                trailing_newlines += 1
                i -= 1
                # Check for \r\n pattern
                if i >= 0 and text[i] == '\r':
                    i -= 1
            elif text[i] == '\r':
                # Standalone \r (old Mac style)
                trailing_newlines += 1
                i -= 1
            else:
                break
        
        # Only fix if there are 2 or more trailing newlines
        # Preserve files with exactly 1 trailing newline
        if trailing_newlines > 1:
            # Remove all trailing newlines and carriage returns, then add back one
            text = text.rstrip('\n\r') + line_ending
            
            # Write back
            with open(file_path, 'wb') as f:
                f.write(text.encode('utf-8'))
            
            return True
        
        # File has 0 or 1 trailing newline - leave it as is
        return False
    
    except Exception as e:
        print(f"Error processing {file_path}: {e}", file=sys.stderr)
        return False

def main():
    """Main function to process all files."""
    if len(sys.argv) > 1:
        root_dir = Path(sys.argv[1])
    else:
        root_dir = Path(__file__).parent.parent
    
    if not root_dir.exists():
        print(f"Error: Directory {root_dir} does not exist", file=sys.stderr)
        sys.exit(1)
    
    fixed_files = []
    processed_count = 0
    
    # Walk through all files
    for file_path in root_dir.rglob('*'):
        if not file_path.is_file():
            continue
        
        if should_process_file(file_path):
            processed_count += 1
            if fix_trailing_newlines(file_path):
                fixed_files.append(file_path)
    
    # Print results
    print(f"Processed {processed_count} files")
    if fixed_files:
        print(f"Fixed {len(fixed_files)} files with multiple trailing newlines:")
        for file_path in fixed_files:
            # Print relative path
            rel_path = file_path.relative_to(root_dir)
            print(f"  {rel_path}")
    else:
        print("No files with multiple trailing newlines found.")
    
    return 0 if fixed_files or processed_count > 0 else 1

if __name__ == '__main__':
    sys.exit(main())
