#!/bin/bash

# Script to run educational_VMEC, jVMEC, and VMEC++ on the same asymmetric input
# with debug output to compare line-by-line for lasym=true cases

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== VMEC Asymmetric Debug Comparison ===${NC}"
echo "This script runs all three VMEC implementations on the same asymmetric input"
echo "and captures debug output for comparison"

# Base directory
BASE_DIR="$(pwd)"
REPOS_DIR="${BASE_DIR}/vmec_repos"

# Create temporary directories for each code
TEMP_DIR="${BASE_DIR}/asymmetric_debug_$(date +%Y%m%d_%H%M%S)"
mkdir -p "${TEMP_DIR}"
mkdir -p "${TEMP_DIR}/educational_vmec"
mkdir -p "${TEMP_DIR}/jvmec"
mkdir -p "${TEMP_DIR}/vmecpp"

echo -e "\n${BLUE}Created temporary directories in: ${TEMP_DIR}${NC}"

# Input file - use the simple SOLOVEV test case modified for lasym=T (asymmetric)
INPUT_FILE="${BASE_DIR}/input.SOLOVEV_asym"

if [ ! -f "$INPUT_FILE" ]; then
    echo -e "${RED}Error: Input file not found: $INPUT_FILE${NC}"
    echo "Trying alternative location..."
    INPUT_FILE="${REPOS_DIR}/educational_VMEC/test/input.test.vmec"
    if [ ! -f "$INPUT_FILE" ]; then
        echo -e "${RED}Error: No symmetric test input found${NC}"
        exit 1
    fi
fi

echo -e "\n${BLUE}Using input file: ${INPUT_FILE}${NC}"
echo "Checking lasym setting:"
grep -i "lasym" "$INPUT_FILE" || echo "lasym not explicitly set (defaults to F - symmetric)"

# Function to run educational_VMEC
run_educational_vmec() {
    echo -e "\n${GREEN}Running Educational VMEC...${NC}"
    cd "${TEMP_DIR}/educational_vmec"
    
    # Copy input file and clean it for educational_VMEC
    cp "$INPUT_FILE" input.SOLOVEV
    # Remove parameters that educational_VMEC doesn't recognize (dump parameters)
    sed -i -e '/dump_/d' input.SOLOVEV
    
    # Run educational_VMEC
    echo "Running: ${REPOS_DIR}/educational_VMEC/build/bin/xvmec input.SOLOVEV"
    "${REPOS_DIR}/educational_VMEC/build/bin/xvmec" input.SOLOVEV 2>&1 | tee educational_vmec_output.log
    
    # Check if it ran successfully
    if [ -f "wout_SOLOVEV.nc" ]; then
        echo -e "${GREEN}✓ Educational VMEC completed successfully${NC}"
    else
        echo -e "${RED}✗ Educational VMEC failed to produce output${NC}"
    fi
}

# Function to run jVMEC
run_jvmec() {
    echo -e "\n${GREEN}Running jVMEC...${NC}"
    cd "${TEMP_DIR}/jvmec"
    
    # Copy input file  
    cp "$INPUT_FILE" input.SOLOVEV
    
    # Clean the input file for jVMEC (remove comments and dump parameters)
    echo "Cleaning input file for jVMEC..."
    sed -e 's/!.*$//' -e '/^$/d' -e '/dump_/d' input.SOLOVEV > input_cleaned.txt
    
    # Run jVMEC
    echo "Running: java -cp ${REPOS_DIR}/jVMEC/target/jVMEC-1.0.0.jar:${REPOS_DIR}/jVMEC/target/dependency/* de.labathome.jvmec.VmecRunner input_cleaned.txt"
    java -cp "${REPOS_DIR}/jVMEC/target/jVMEC-1.0.0.jar:${REPOS_DIR}/jVMEC/target/dependency/*" de.labathome.jvmec.VmecRunner input_cleaned.txt 2>&1 | tee jvmec_output.log
    
    # Check if it ran successfully  
    if [ -f "wout_input_cleaned.nc" ]; then
        echo -e "${GREEN}✓ jVMEC completed successfully${NC}"
    else
        echo -e "${RED}✗ jVMEC failed to produce output${NC}"
    fi
}

# Function to run VMEC++
run_vmecpp() {
    echo -e "\n${GREEN}Running VMEC++...${NC}"
    cd "${TEMP_DIR}/vmecpp"
    
    # Copy input file
    cp "$INPUT_FILE" input.SOLOVEV
    
    # Convert to JSON format for VMEC++
    echo "Converting input to JSON format for VMEC++..."
    python3 -m vmecpp.input2json input.SOLOVEV SOLOVEV.json
    
    # Run VMEC++
    echo "Running: /home/ert/code/vmecpp/build/vmec_standalone -i SOLOVEV.json -o SOLOVEV.out.h5"
    "/home/ert/code/vmecpp/build/vmec_standalone" -i SOLOVEV.json -o SOLOVEV.out.h5 2>&1 | tee vmecpp_output.log
    
    # Check if it ran successfully
    if [ -f "SOLOVEV.out.h5" ]; then
        echo -e "${GREEN}✓ VMEC++ completed successfully${NC}"
    else
        echo -e "${RED}✗ VMEC++ failed to produce output${NC}"
    fi
}

# Function to extract debug output
extract_debug_output() {
    echo -e "\n${BLUE}Extracting debug output for comparison...${NC}"
    
    # Extract educational_VMEC debug output
    if [ -f "${TEMP_DIR}/educational_vmec/educational_vmec_output.log" ]; then
        echo -e "\n${GREEN}Educational VMEC debug output:${NC}"
        grep -E "DEBUG:|ERROR:|First few|NaN detected|totzspa|asymmetric transform" "${TEMP_DIR}/educational_vmec/educational_vmec_output.log" > "${TEMP_DIR}/educational_vmec_debug.txt" || true
        head -20 "${TEMP_DIR}/educational_vmec_debug.txt" || echo "No debug output found"
    fi
    
    # Extract jVMEC debug output
    if [ -f "${TEMP_DIR}/jvmec/jvmec_output.log" ]; then
        echo -e "\n${GREEN}jVMEC debug output:${NC}"
        grep -E "DEBUG:|ERROR:|First few|NaN detected|asymmetric|BSQ|tomnspa|symforce" "${TEMP_DIR}/jvmec/jvmec_output.log" > "${TEMP_DIR}/jvmec_debug.txt" || true
        head -20 "${TEMP_DIR}/jvmec_debug.txt" || echo "No debug output found"
    fi
    
    # Extract VMEC++ debug output
    if [ -f "${TEMP_DIR}/vmecpp/vmecpp_output.log" ]; then
        echo -e "\n${GREEN}VMEC++ debug output:${NC}"
        grep -E "DEBUG:|ERROR:|First few|NaN detected|asymmetric|FourierToReal|RealToFourier" "${TEMP_DIR}/vmecpp/vmecpp_output.log" > "${TEMP_DIR}/vmecpp_debug.txt" || true
        head -20 "${TEMP_DIR}/vmecpp_debug.txt" || echo "No debug output found"
    fi
    
    # Compare convergence and final values
    echo -e "\n${BLUE}Convergence Comparison:${NC}"
    echo "Educational VMEC final iteration:"
    tail -10 "${TEMP_DIR}/educational_vmec/educational_vmec_output.log" | grep -E "ITER|EXECUTION" || true
    
    echo "jVMEC final iteration:"
    tail -10 "${TEMP_DIR}/jvmec/jvmec_output.log" | grep -E "converged|time for equilibrium" || true
    
    echo "VMEC++ final iteration:"
    tail -10 "${TEMP_DIR}/vmecpp/vmecpp_output.log" | grep -E "converged|completed" || true
}

# Main execution
echo -e "\n${BLUE}Starting VMEC comparisons...${NC}"

# Check if executables exist
if [ ! -f "${REPOS_DIR}/educational_VMEC/build/bin/xvmec" ]; then
    echo -e "${RED}Educational VMEC executable not found. Building...${NC}"
    cd "${REPOS_DIR}/educational_VMEC"
    mkdir -p build && cd build
    cmake .. && make -j
    cd "$BASE_DIR"
fi

if [ ! -f "${REPOS_DIR}/jVMEC/target/jVMEC-1.0.0.jar" ]; then
    echo -e "${RED}jVMEC JAR not found. Building...${NC}"
    cd "${REPOS_DIR}/jVMEC"
    ./build.sh
    cd "$BASE_DIR"
fi

if [ ! -f "/home/ert/code/vmecpp/build/vmec_standalone" ]; then
    echo -e "${RED}VMEC++ executable not found. Please build it first.${NC}"
    exit 1
fi

# Run all three codes
run_educational_vmec
run_jvmec
run_vmecpp

# Extract and compare debug output
extract_debug_output

echo -e "\n${BLUE}=== Summary ===${NC}"
echo "Results saved in: ${TEMP_DIR}"
echo "- Educational VMEC: ${TEMP_DIR}/educational_vmec/"
echo "- jVMEC: ${TEMP_DIR}/jvmec/"
echo "- VMEC++: ${TEMP_DIR}/vmecpp/"

echo -e "\n${BLUE}Debug output comparison files:${NC}"
echo "- ${TEMP_DIR}/educational_vmec_debug.txt"
echo "- ${TEMP_DIR}/jvmec_debug.txt"
echo "- ${TEMP_DIR}/vmecpp_debug.txt"

echo -e "\n${BLUE}To compare debug outputs side by side:${NC}"
echo "diff -y ${TEMP_DIR}/educational_vmec_debug.txt ${TEMP_DIR}/jvmec_debug.txt"
echo "diff -y ${TEMP_DIR}/jvmec_debug.txt ${TEMP_DIR}/vmecpp_debug.txt"

echo -e "\n${GREEN}Asymmetric comparison complete!${NC}"
echo "This compares asymmetric (lasym=T) implementations to identify"
echo "differences in Fourier transforms, force calculations, and convergence behavior."