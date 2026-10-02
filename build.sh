#!/usr/bin/env bash
#
# build.sh - Build and test automation script for mtkclient
# Automates source archiving, RPM compilation, and artifact verification.
#

set -euo pipefail

# Text formatting
BOLD="\033[1m"
GREEN="\033[0;32m"
BLUE="\033[0;34m"
YELLOW="\033[0;33m"
RED="\033[0;31m"
NC="\033[0m" # No Color

info() {
    echo -e "${BLUE}${BOLD}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}${BOLD}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}${BOLD}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}${BOLD}[ERROR]${NC} $*" >&2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPEC_FILE="${SCRIPT_DIR}/mtkclient.spec"
DESKTOP_FILE="${SCRIPT_DIR}/mtk_gui.desktop"
RPMBUILD_DIR="${HOME}/rpmbuild"

# Flags
DO_RPM=true
DO_WHEEL=false
DO_TEST=true
DO_CLEAN=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automate compilation, packaging, and testing of mtkclient.

Options:
  -r, --rpm          Build RPM package (default: true)
  -w, --wheel        Build Python wheel package (default: false)
  -t, --test         Run verification tests on built artifacts (default: true)
  --no-test          Skip artifact verification tests
  -c, --clean        Clean build directories and temporary files
  -h, --help         Show this help message and exit

Examples:
  ./build.sh                  # Build RPM and run tests (standard)
  ./build.sh --wheel          # Build RPM and Python wheel
  ./build.sh --clean          # Clean local build directories
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -r|--rpm)
            DO_RPM=true
            shift
            ;;
        -w|--wheel)
            DO_WHEEL=true
            shift
            ;;
        -t|--test)
            DO_TEST=true
            shift
            ;;
        --no-test)
            DO_TEST=false
            shift
            ;;
        -c|--clean)
            DO_CLEAN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Perform clean if requested
if [ "${DO_CLEAN}" = true ]; then
    info "Cleaning build artifacts in repository..."
    rm -rf "${SCRIPT_DIR}/build" "${SCRIPT_DIR}/dist" "${SCRIPT_DIR}"/*.egg-info "${SCRIPT_DIR}"/.test_rpm_*
    success "Clean completed."
    exit 0
fi

# Ensure spec and desktop files exist
if [ ! -f "${SPEC_FILE}" ]; then
    error "Spec file not found at ${SPEC_FILE}"
    exit 1
fi

if [ ! -f "${DESKTOP_FILE}" ]; then
    error "Desktop entry file not found at ${DESKTOP_FILE}"
    exit 1
fi

# Extract package metadata from spec file
PKG_NAME="$(sed -n 's/^Name:[[:space:]]*//p' "${SPEC_FILE}" | head -n1 | tr -d '[:space:]')"
PKG_VERSION="$(sed -n 's/^Version:[[:space:]]*//p' "${SPEC_FILE}" | head -n1 | tr -d '[:space:]')"

info "Package: ${BOLD}${PKG_NAME}${NC} (v${PKG_VERSION})"

# Check essential prerequisites
info "Checking build tools..."
MISSING_TOOLS=()
for tool in git rpmbuild tar python3 rpm2cpio cpio desktop-file-validate; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        MISSING_TOOLS+=("${tool}")
    fi
done

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    error "Missing required build tools: ${MISSING_TOOLS[*]}"
    error "Please install them via: sudo dnf install -y rpm-build rpmdevtools git tar python3 desktop-file-utils"
    exit 1
fi

# 1. Build RPM Package
if [ "${DO_RPM}" = true ]; then
    info "Preparing rpmbuild directories in ${RPMBUILD_DIR}..."
    mkdir -p "${RPMBUILD_DIR}"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
    mkdir -p "${SCRIPT_DIR}/dist"

    TARBALL_NAME="${PKG_NAME}-${PKG_VERSION}.tar.gz"
    TARBALL_PATH="${RPMBUILD_DIR}/SOURCES/${TARBALL_NAME}"

    info "Creating source archive: ${TARBALL_PATH}..."
    git -C "${SCRIPT_DIR}" archive --format=tar.gz --prefix="${PKG_NAME}-${PKG_VERSION}/" HEAD -o "${TARBALL_PATH}"

    info "Staging spec file and desktop entry..."
    cp -p "${SPEC_FILE}" "${RPMBUILD_DIR}/SPECS/${PKG_NAME}.spec"
    cp -p "${DESKTOP_FILE}" "${RPMBUILD_DIR}/SOURCES/mtk_gui.desktop"

    info "Compiling RPM package with rpmbuild..."
    rpmbuild -ba "${RPMBUILD_DIR}/SPECS/${PKG_NAME}.spec"

    # Locate generated RPMs
    BUILT_RPM="$(find "${RPMBUILD_DIR}/RPMS" -type f -name "${PKG_NAME}-${PKG_VERSION}-*.rpm" | head -n1)"
    BUILT_SRPM="$(find "${RPMBUILD_DIR}/SRPMS" -type f -name "${PKG_NAME}-${PKG_VERSION}-*.src.rpm" | head -n1)"

    if [ -z "${BUILT_RPM}" ] || [ ! -f "${BUILT_RPM}" ]; then
        error "Failed to locate generated binary RPM!"
        exit 1
    fi

    # Copy to project dist/ directory for convenience
    cp -p "${BUILT_RPM}" "${SCRIPT_DIR}/dist/"
    if [ -n "${BUILT_SRPM}" ] && [ -f "${BUILT_SRPM}" ]; then
        cp -p "${BUILT_SRPM}" "${SCRIPT_DIR}/dist/"
    fi

    success "Binary RPM built successfully: ${BUILT_RPM}"
    if [ -n "${BUILT_SRPM}" ] && [ -f "${BUILT_SRPM}" ]; then
        success "Source RPM built successfully: ${BUILT_SRPM}"
    fi
fi

# 2. Build Python Wheel (if requested)
if [ "${DO_WHEEL}" = true ]; then
    info "Building Python wheel..."
    python3 -m pip wheel --no-deps -w "${SCRIPT_DIR}/dist" "${SCRIPT_DIR}"
    WHEEL_FILE="$(find "${SCRIPT_DIR}/dist" -type f -name "${PKG_NAME}-${PKG_VERSION}-*.whl" | head -n1)"
    success "Python wheel built: ${WHEEL_FILE}"
fi

# 3. Automated Testing and Verification
if [ "${DO_TEST}" = true ] && [ "${DO_RPM}" = true ]; then
    info "Running automated verification tests on ${BUILT_RPM}..."

    # Check RPM header info
    rpm -qip "${BUILT_RPM}" >/dev/null
    info "RPM metadata queried successfully."

    # Verify file manifest
    RPM_FILES="$(rpm -qlp "${BUILT_RPM}")"
    EXPECTED_FILES=(
        "/usr/bin/mtk"
        "/usr/bin/mtk.py"
        "/usr/bin/mtk_gui"
        "/usr/bin/mtk_gui.py"
        "/usr/bin/stage2"
        "/usr/bin/stage2.py"
        "/usr/bin/da_parser"
        "/usr/bin/brom_to_offs"
        "/usr/lib/udev/rules.d/52-mtk.rules"
        "/usr/lib/udev/rules.d/51-edl.rules"
        "/usr/share/applications/mtk_gui.desktop"
        "/usr/share/icons/hicolor/256x256/apps/mtkclient.png"
    )

    for expected in "${EXPECTED_FILES[@]}"; do
        if ! grep -Fxq "${expected}" <<< "${RPM_FILES}"; then
            error "Expected file ${expected} is missing from RPM package!"
            exit 1
        fi
    done
    info "Package manifest contains all expected CLI binaries, desktop entries, and udev rules."

    # Extract RPM into isolated temp directory for sandbox verification
    TEST_TMPDIR="$(mktemp -d -p "${SCRIPT_DIR}" .test_rpm_XXXXXX)"
    trap 'rm -rf "${TEST_TMPDIR}"' EXIT

    (
        cd "${TEST_TMPDIR}"
        rpm2cpio "${BUILT_RPM}" | cpio -idm --quiet
    )

    # 1. Verify desktop file syntax
    EXTRACTED_DESKTOP="${TEST_TMPDIR}/usr/share/applications/mtk_gui.desktop"
    if [ -f "${EXTRACTED_DESKTOP}" ]; then
        desktop-file-validate "${EXTRACTED_DESKTOP}"
        info "Extracted desktop file validated successfully."
    fi

    # 2. Verify executables and shebangs
    for bin_name in mtk mtk_gui stage2; do
        BIN_PATH="${TEST_TMPDIR}/usr/bin/${bin_name}"
        if [ ! -x "${BIN_PATH}" ]; then
            error "Binary ${BIN_PATH} is not executable!"
            exit 1
        fi

        SHEBANG="$(head -n1 "${BIN_PATH}")"
        if [[ "${SHEBANG}" != *"python3"* ]]; then
            error "Invalid shebang in ${BIN_PATH}: ${SHEBANG}"
            exit 1
        fi
    done
    info "Entry-point scripts and Python 3 shebangs verified."

    # 3. Verify udev rules exist and contain expected vendor IDs
    MTK_UDEV="${TEST_TMPDIR}/usr/lib/udev/rules.d/52-mtk.rules"
    if [ ! -f "${MTK_UDEV}" ] || ! grep -q "0e8d" "${MTK_UDEV}"; then
        error "MediaTek udev rules verification failed in ${MTK_UDEV}"
        exit 1
    fi
    info "MediaTek udev rules verified (MTK Vendor ID 0e8d present)."

    # 4. Test Python package import in isolated environment
    SITELIB_DIR="$(find "${TEST_TMPDIR}/usr" -type d -path "*/site-packages/mtkclient" | head -n1)"
    if [ -n "${SITELIB_DIR}" ]; then
        PARENT_SITELIB="$(dirname "${SITELIB_DIR}")"
        PYTHONPATH="${PARENT_SITELIB}" python3 -c "import mtkclient; print('mtkclient import OK')"
        info "Verified isolated Python module import from site-packages."
    fi

    # Clean up test tempdir
    rm -rf "${TEST_TMPDIR}"
    trap - EXIT

    success "All automated verification tests passed!"
fi

# Print final summary
echo ""
echo -e "${GREEN}${BOLD}======================================================${NC}"
echo -e "${GREEN}${BOLD}               BUILD & TEST COMPLETE                  ${NC}"
echo -e "${GREEN}${BOLD}======================================================${NC}"
if [ "${DO_RPM}" = true ]; then
    echo -e "${BOLD}Binary RPM:${NC} ${BUILT_RPM}"
    echo -e "${BOLD}Local Copy:${NC} ${SCRIPT_DIR}/dist/$(basename "${BUILT_RPM}")"
    if [ -n "${BUILT_SRPM:-}" ]; then
        echo -e "${BOLD}Source RPM:${NC} ${BUILT_SRPM}"
    fi
    echo ""
    echo -e "${BOLD}To install on your system:${NC}"
    echo -e "  sudo dnf install ${BUILT_RPM}"
    echo ""
    echo -e "${BOLD}To reload udev rules and configure user permissions:${NC}"
    echo -e "  sudo udevadm control --reload-rules && sudo udevadm trigger"
    echo -e "  sudo usermod -aG dialout,plugdev \$USER"
    echo ""
    echo -e "${BOLD}To verify installed binary:${NC}"
    echo -e "  mtk --help"
    echo -e "  mtk_gui"
fi
echo -e "${GREEN}${BOLD}======================================================${NC}"
