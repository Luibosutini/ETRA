#!/bin/bash
set -euo pipefail
echo "=== 07-matlab start: $(date) ==="

: "${MATLAB_RELEASE:=R2024b}"
: "${MATLAB_PRODUCTS:=MATLAB Simulink Image_Processing_Toolbox Signal_Processing_Toolbox Statistics_and_Machine_Learning_Toolbox Optimization_Toolbox Parallel_Computing_Toolbox Curve_Fitting_Toolbox Control_System_Toolbox}"

curl -fsSL -o /tmp/mpm https://www.mathworks.com/mpm/glnxa64/mpm
chmod +x /tmp/mpm

mkdir -p /opt/matlab

# MATLAB licensing/authentication is intentionally deferred to runtime user sign-in.
/tmp/mpm install --release="$MATLAB_RELEASE" --destination=/opt/matlab --products $MATLAB_PRODUCTS

ln -sf /opt/matlab/bin/matlab /usr/local/bin/matlab

rm -f /tmp/mpm

echo "=== 07-matlab done: $(date) ==="
