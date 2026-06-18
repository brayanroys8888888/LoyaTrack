import os
import re

lib_dir = r'c:\projects\fullstack_projects\Loyatrack_django_and_flutter\frontend\papillongestion\lib'

modified_files = []

for root, dirs, files in os.walk(lib_dir):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            orig_content = content
            
            # trailing comma
            content = re.sub(r"fontFamily:\s*'[A-Za-z]+',\s*", "", content)
            # leading comma
            content = re.sub(r",\s*fontFamily:\s*'[A-Za-z]+'", "", content)
            # just the arg
            content = re.sub(r"fontFamily:\s*'[A-Za-z]+'", "", content)
            
            if content != orig_content:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(content)
                modified_files.append(file)

print('Modified:', modified_files)
