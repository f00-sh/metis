#!/usr/bin/env python3
"""Extract text from xlsx using stdlib only."""
import zipfile, xml.etree.ElementTree as ET, sys
path = sys.argv[1]
NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
try:
    z = zipfile.ZipFile(path)
    ss = []
    if "xl/sharedStrings.xml" in z.namelist():
        root = ET.fromstring(z.read("xl/sharedStrings.xml"))
        for si in root.findall("m:si", NS):
            texts = [
                t.text or ""
                for t in si.iter(
                    "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}t"
                )
            ]
            ss.append("".join(texts))
    out = []
    for name in z.namelist():
        if name.startswith("xl/worksheets/sheet") and name.endswith(".xml"):
            root = ET.fromstring(z.read(name))
            rows = []
            for row in root.findall(".//m:row", NS):
                cells = []
                for c in row.findall("m:c", NS):
                    t = c.get("t")
                    v = c.find("m:v", NS)
                    if v is None or v.text is None:
                        cells.append("")
                    elif t == "s":
                        try:
                            cells.append(ss[int(v.text)])
                        except Exception:
                            cells.append(v.text)
                    else:
                        cells.append(v.text)
                if any(cells):
                    rows.append("\t".join(cells))
            if rows:
                out.append(name + ":\n" + "\n".join(rows))
    print("\n\n".join(out))
except Exception as e:
    sys.stderr.write(str(e))
    sys.exit(1)
