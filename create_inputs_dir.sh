#!/bin/bash

# Create VMEC Input Files Directory
echo "Creating VMEC Input Files Directory..."

# Find all input files excluding jVMEC
find vmec_repos/ -path '*/jvmec*' -prune -o -name 'input*' -type f -print > input_files_list.tmp

echo "# VMEC Input Files Directory" > inputs.md
echo "" >> inputs.md
echo "Comprehensive listing of VMEC input files with key parameters (excluding jVMEC)" >> inputs.md
echo "" >> inputs.md
echo "| File Path | Full Path | LASYM | NFP | MPOL | NTOR | NS | PHIEDGE | Notes |" >> inputs.md
echo "|-----------|-----------|-------|-----|------|------|----|---------| ------|" >> inputs.md

# Process each input file
while IFS= read -r file; do
    if [[ -f "$file" ]]; then
        # Extract filename
        filename=$(basename "$file")
        
        # Initialize variables
        lasym="?"
        nfp="?"
        mpol="?"
        ntor="?"
        ns="?"
        phiedge="?"
        notes=""
        
        # Extract parameters using grep and awk
        if grep -q "&INDATA\|&indata" "$file" 2>/dev/null; then
            # Extract LASYM
            lasym_line=$(grep -i "lasym" "$file" | grep -v "^!" | head -1)
            if [[ -n "$lasym_line" ]]; then
                lasym=$(echo "$lasym_line" | sed 's/.*=//' | sed 's/,.*$//' | tr -d ' ')
            fi
            
            # Extract NFP
            nfp_line=$(grep -i "nfp" "$file" | grep -v "^!" | head -1)
            if [[ -n "$nfp_line" ]]; then
                nfp=$(echo "$nfp_line" | sed 's/.*=//' | sed 's/,.*$//' | tr -d ' ')
            fi
            
            # Extract MPOL
            mpol_line=$(grep -i "mpol" "$file" | grep -v "^!" | head -1)
            if [[ -n "$mpol_line" ]]; then
                mpol=$(echo "$mpol_line" | sed 's/.*=//' | sed 's/,.*$//' | tr -d ' ')
            fi
            
            # Extract NTOR
            ntor_line=$(grep -i "ntor" "$file" | grep -v "^!" | head -1)
            if [[ -n "$ntor_line" ]]; then
                ntor=$(echo "$ntor_line" | sed 's/.*=//' | sed 's/,.*$//' | tr -d ' ')
            fi
            
            # Extract NS_ARRAY (first value)
            ns_line=$(grep -i "ns_array\|ns =" "$file" | grep -v "^!" | head -1)
            if [[ -n "$ns_line" ]]; then
                ns=$(echo "$ns_line" | sed 's/.*=//' | awk '{print $1}' | sed 's/,.*$//')
            fi
            
            # Extract PHIEDGE
            phiedge_line=$(grep -i "phiedge" "$file" | grep -v "^!" | head -1)
            if [[ -n "$phiedge_line" ]]; then
                phiedge=$(echo "$phiedge_line" | sed 's/.*=//' | sed 's/,.*$//' | tr -d ' ')
            fi
        fi
        
        # Add notes based on characteristics
        if [[ "$lasym" == "T" || "$lasym" == ".TRUE." || "$lasym" == "true" ]]; then
            notes="${notes}Non-axisymmetric; "
        fi
        
        if [[ "$file" == *"free"* ]]; then
            notes="${notes}Free boundary; "
        fi
        
        if [[ "$file" == *"fixed"* ]]; then
            notes="${notes}Fixed boundary; "
        fi
        
        if [[ "$file" == *"tokamak"* ]]; then
            notes="${notes}Tokamak; "
        fi
        
        if [[ "$file" == *"stellarator"* || "$file" == *"W7X"* ]]; then
            notes="${notes}Stellarator; "
        fi
        
        if [[ "$file" == *"ITER"* ]]; then
            notes="${notes}ITER; "
        fi
        
        if [[ "$file" == *"heliotron"* || "$file" == *"HELIOTRON"* ]]; then
            notes="${notes}Heliotron; "
        fi
        
        if [[ "$file" == *"low_res"* ]]; then
            notes="${notes}Low resolution; "
        fi
        
        if [[ "$file" == *"high_res"* ]]; then
            notes="${notes}High resolution; "
        fi
        
        # Write the row
        echo "| $filename | $file | $lasym | $nfp | $mpol | $ntor | $ns | $phiedge | $notes |" >> inputs.md
    fi
done < input_files_list.tmp

# Cleanup
rm -f input_files_list.tmp

echo "Input directory saved to inputs.md"

# Count files with LASYM=T
echo ""
echo "Summary:"
total_files=$(grep -c "^|" inputs.md)
((total_files--))  # Subtract header row
lasym_true=$(grep -c "| T |" inputs.md)
lasym_false=$(grep -c "| F |" inputs.md)

echo "Total input files: $total_files"
echo "LASYM = T (non-axisymmetric): $lasym_true"
echo "LASYM = F (axisymmetric): $lasym_false"