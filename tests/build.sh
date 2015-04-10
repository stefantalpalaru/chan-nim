#!/bin/bash

set -euo pipefail


nim c --threads:on -p:"../src" chan_test.nim

