#!/bin/sh
# Runs the ECMDroid iOS test suite against a private ecmsim instance.
#
# Compiles the app's transport/protocol/model/database sources together with
# Tests/*.swift into a macOS test binary, starts ecmsim on a dedicated port
# (6299, so it never fights your interactive simulator on 6275), runs the
# suite, and tears everything down. Exit code 0 = all tests passed.
#
#   ./run-tests.sh            # run everything
set -e
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ECMSIM_DIR="$SCRIPT_DIR/ecmsim"
TEST_PORT=${TEST_PORT:-6299}

# --- Java (Homebrew keg-only OpenJDK) ---------------------------------------
if [ -d "/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home" ]; then
    export JAVA_HOME="/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home"
    export PATH="$JAVA_HOME/bin:$PATH"
fi
if ! command -v java >/dev/null 2>&1; then
    echo "Java not found. Install it with: brew install openjdk" >&2
    exit 1
fi
if [ ! -d "$ECMSIM_DIR" ]; then
    echo "Cloning ecmsim (Buell ECM simulator)..."
    git clone --depth 1 https://github.com/ecmdroid/ecmsim.git "$ECMSIM_DIR"
fi
if ! grep -q "Client disconnected during connection setup" "$ECMSIM_DIR/src/main/java/org/ecmdroid/sim/Main.java"; then
    echo "Applying ecmsim resilience patch..."
    git -C "$ECMSIM_DIR" apply "$SCRIPT_DIR/patches/ecmsim-survive-client-reset.patch"
    rm -rf "$ECMSIM_DIR/target"
fi
if [ ! -f "$ECMSIM_DIR/target/ecmsim.jar" ]; then
    echo "Building ecmsim (one-time)..."
    (cd "$ECMSIM_DIR" && ./mvnw -q clean package)
fi

# --- Test workspace ----------------------------------------------------------
WORKDIR=$(mktemp -d /tmp/ecmdroid-tests.XXXXXX)
mkdir -p "$WORKDIR/home"
cleanup() {
    [ -n "$SIM_PID" ] && kill "$SIM_PID" 2>/dev/null || true
    rm -rf "$WORKDIR"
}
trap cleanup EXIT INT TERM

# --- Compile the suite (app sources + tests, for macOS) ----------------------
echo "Compiling test suite..."
cd "$SCRIPT_DIR"
swiftc -parse-as-library -o "$WORKDIR/ecmtests" \
    ECMDroid/Transport/SerialPort.swift \
    ECMDroid/Transport/TCPSerialPort.swift \
    ECMDroid/Protocol/PDU.swift \
    ECMDroid/Protocol/ECMCommand.swift \
    ECMDroid/Model/Constants.swift \
    ECMDroid/Model/EEPROM.swift \
    ECMDroid/Model/ECMError.swift \
    ECMDroid/Model/EEPROMBackup.swift \
    ECMDroid/Model/Variable.swift \
    ECMDroid/Model/BitModel.swift \
    ECMDroid/Model/BitSetModel.swift \
    ECMDroid/Model/TorqueData.swift \
    ECMDroid/Model/LogExporter.swift \
    ECMDroid/Model/ECM.swift \
    "ECMDroid/Model/ECM+EEPROMEditing.swift" \
    ECMDroid/Database/DatabaseManager.swift \
    ECMDroid/Database/EEPROMProvider.swift \
    ECMDroid/Database/VariableProvider.swift \
    ECMDroid/Database/BitSetProvider.swift \
    ECMDroid/BLE/BLEAdapterProtocol.swift \
    ECMDroid/BLE/BLEManager.swift \
    ECMDroid/BLE/BLESerialPort.swift \
    ECMDroid/BLE/Adapters/CC254xAdapter.swift \
    ECMDroid/BLE/Adapters/NRFAdapter.swift \
    ECMDroid/BLE/Adapters/RN4870Adapter.swift \
    ECMDroid/BLE/Adapters/TelitTIOAdapter.swift \
    Tests/TestSupport.swift \
    Tests/UnitTests.swift \
    Tests/IntegrationTests.swift \
    Tests/TestMain.swift

# The database loads via Bundle.main, which for a CLI binary is its directory
cp ECMDroid/Resources/ecmdroid.db "$WORKDIR/"

# --- Start a private simulator ----------------------------------------------
echo "Starting ecmsim on port $TEST_PORT..."
java -jar "$ECMSIM_DIR/target/ecmsim.jar" -p "$TEST_PORT" BUEIB > "$WORKDIR/ecmsim.log" 2>&1 &
SIM_PID=$!
i=0
until nc -z 127.0.0.1 "$TEST_PORT" 2>/dev/null; do
    i=$((i + 1))
    if [ $i -gt 50 ] || ! kill -0 "$SIM_PID" 2>/dev/null; then
        echo "ecmsim failed to start; log follows:" >&2
        cat "$WORKDIR/ecmsim.log" >&2
        exit 1
    fi
    sleep 0.2
done

# --- Run ---------------------------------------------------------------------
# HOME is sandboxed so EEPROM backups land in the workspace, not ~/Documents.
set +e
HOME="$WORKDIR/home" ECMSIM_PORT="$TEST_PORT" "$WORKDIR/ecmtests"
RESULT=$?
set -e
if [ $RESULT -ne 0 ] && [ -s "$WORKDIR/ecmsim.log" ]; then
    echo ""
    echo "--- last ecmsim log lines ---"
    tail -5 "$WORKDIR/ecmsim.log"
fi
exit $RESULT
