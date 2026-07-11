#!/bin/sh
# Starts the ecmsim Buell ECM simulator for testing the ECMDroid iOS app
# without the bike. No arguments needed: simulates a BUEIB on port 6275
# with debug output. Any arguments are passed straight to ecmsim, e.g.:
#   ./run-ecmsim.sh --list        # show all supported ECM models
#   ./run-ecmsim.sh BUE2D         # simulate a different model
#   ./run-ecmsim.sh -p 7000 BUEIB # different port
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ECMSIM_DIR="$SCRIPT_DIR/ecmsim"

# Homebrew's OpenJDK is keg-only (not on PATH by default)
if [ -d "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" ]; then
    export JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
    export PATH="$JAVA_HOME/bin:$PATH"
fi
if ! command -v java >/dev/null 2>&1; then
    echo "Java not found. Install it with: brew install openjdk" >&2
    exit 1
fi

# Fetch the simulator on first use; it is not part of this repository
if [ ! -d "$ECMSIM_DIR" ]; then
    echo "Cloning ecmsim (Buell ECM simulator)..."
    git clone --depth 1 https://github.com/ecmdroid/ecmsim.git "$ECMSIM_DIR"
fi
# Local patch (see patches/): keeps the simulator alive when a client
# resets during connection setup instead of crashing the whole process
if ! grep -q "Client disconnected during connection setup" "$ECMSIM_DIR/src/main/java/org/ecmdroid/sim/Main.java"; then
    echo "Applying ecmsim resilience patch..."
    git -C "$ECMSIM_DIR" apply "$SCRIPT_DIR/patches/ecmsim-survive-client-reset.patch"
    rm -rf "$ECMSIM_DIR/target" # force a rebuild with the patch
fi

# Build the jar on first run (or after a git clean)
if [ ! -f "$ECMSIM_DIR/target/ecmsim.jar" ]; then
    echo "ecmsim.jar not found - building (one-time)..."
    (cd "$ECMSIM_DIR" && ./mvnw -q clean package)
fi

if [ $# -eq 0 ]; then
    set -- -d BUEIB
fi

LAN_IP=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "<this Mac's IP>")
cat <<EOF
------------------------------------------------------------------
 ECM simulator: $*  (port 6275 unless -p given)

 In the app: Connect tab -> "ECM Simulator (TCP)" -> Connect
   from the iOS Simulator:  host 127.0.0.1
   from a physical iPhone:  host $LAN_IP  (same Wi-Fi as this Mac)

 Stop with Ctrl-C.
------------------------------------------------------------------
EOF
exec "$ECMSIM_DIR/ecmsim.sh" "$@"
