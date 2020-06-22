#!/bin/bash

diff -ruN -X /usr/share/eprints/bin/difflocal.exclude /usr/share/eprints/archives/researchdata/cfg /usr/share/eprints/archives/rdtest/cfg | tee /usr/share/eprints/bin/sync_l2t.patch
