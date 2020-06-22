#!/bin/bash
diff $1 -X /usr/share/eprints/bin/difflocal.exclude -r /usr/share/eprints/archives/rdtest/cfg /usr/share/eprints/archives/researchdata/cfg
