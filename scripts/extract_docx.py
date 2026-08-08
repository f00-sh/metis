#!/usr/bin/env python3
import zipfile, xml.etree.ElementTree as ET, sys, re
path = sys.argv[1]
try:
    z = zipfile.ZipFile(path)
    root = ET.fromstring(z.read("word/document.xml"))
    texts = []
    for t in root.iter("{http://schemas.openxmlformats.org/wordprocessingml/2006/main}t"):
        if t.text:
            texts.append(t.text)
        if t.tail:
            texts.append(t.tail)
    print(re.sub(r"[ \t]+", " ", "\n".join(texts)))
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
