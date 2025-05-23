tableMenu() {
    db_name="$1"

    while true; do
        choice=$(kdialog --title "Database: $db_name" --menu "Manage Tables in $db_name" \
            1 "Create Table" \
            2 "List Tables" \
            3 "Drop Table" \
            4 "Insert into Table" \
            5 "Select From Table" \
            6 "Delete From Table" \
            7 "Update Table" \
            8 "Back to Main Menu" \
            9 "Exit Program" --default "Create Table")

        case "$choice" in
        1) createTable "$db_name" ;;
        2) listTables "$db_name" ;;
        3) dropTable "$db_name" ;;
        4) insertIntoTable "$db_name" ;;
        5) selectFromTable "$db_name" ;;
        6) deleteFromTable "$db_name" ;;
        7) updateTable "$db_name" ;;
        8) break ;;
        9 | "") exit 0 ;;
        *) kdialog --sorry "Invalid Choice" ;;
        esac
    done
    cd "$HOME/databases"
}

createTable() {
    db_name="$1"

    table_name=$(kdialog --inputbox "Enter Table Name:")
    [[ $? -ne 0 ]] && return

    table_name=$(echo "$table_name" | awk '{$1=$1;print}')

    if [[ ! "$table_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
        kdialog --sorry "Error: Table name can only contain letters, numbers, and underscores."
        return
    fi

    if [[ -f "$db_name/$table_name.table" ]]; then
        kdialog --sorry "Error: Table already exists."
        return
    fi

    num_cols=$(kdialog --inputbox "Enter Number of Columns:")
    [[ $? -ne 0 ]] && return

    if ! [[ "$num_cols" =~ ^[1-9][0-9]*$ ]]; then
        kdialog --sorry "Error: Invalid column number."
        return
    fi

    cols=()
    col_defs=()
    pk_column=""

    for ((i = 1; i <= num_cols; i++)); do
        while true; do
            col_name=$(kdialog --inputbox "Enter name for column $i:")
            [[ $? -ne 0 ]] && return

            col_name=$(echo "$col_name" | awk '{$1=$1;print}')

            # Check if column name is valid
            if [[ ! "$col_name" =~ ^[a-zA-Z0-9_]+$ ]]; then
                kdialog --sorry "Error: Column name can only contain letters, numbers, and underscores."
                continue
            fi

            # Check if column name is unique
            if [[ " ${cols[*]} " =~ " $col_name " ]]; then
                kdialog --sorry "Error: Column '$col_name' already exists. Choose another name."
                continue
            fi

            break
        done

        cols+=("$col_name") # Store column name

        col_type=$(kdialog --menu "Select data type for $col_name" 1 "int" 2 "string")
        [[ $? -ne 0 ]] && return

        if [[ -z "$pk_column" ]]; then
            kdialog --yesno "Is $col_name the primary key?"
            response=$?

            if [[ $response -eq 0 ]]; then
                pk_column="$col_name"
                col_defs+=("$col_name:$col_type:PK")
            elif [[ $response -eq 1 ]]; then
                col_defs+=("$col_name:$col_type")
            else
                return
            fi
        else
            col_defs+=("$col_name:$col_type")
        fi

    done

    if [[ -z "$pk_column" ]]; then
        kdialog --sorry "Error: You must select at least one column as the Primary Key."
        return
    fi

    echo "${col_defs[*]}" | tr ' ' '|' >"$db_name/$table_name.meta"
    touch "$db_name/$table_name.table"

    kdialog --msgbox "Table '$table_name' created successfully in database '$db_name'."
}

checkIfTableExists() {
    db_name="$1"
    table_dir="$HOME/databases/$db_name"
    tables=$(ls "$table_dir"/*.table | sed 's#.*/##' | sed 's#.table##')

    if [ -z "$tables" ]; then
        kdialog --sorry "No tables found in database '$db_name'."
        return
    fi

    table_menu=()
    index=1
    for table in $tables; do
        table_menu+=("$index" "$table")
        ((index++))
    done
}

listTables() {
    checkIfTableExists "$db_name"
    [ -z "$tables" ] && return
    echo "$tables" | awk '
    BEGIN {print "Tables in '"$db_name"':\n"} 
    {print "\t" NR ": " $1 "\n\t-----------------"} 
    END {print "\nTotal Tables: " NR}
    ' >.tableNames.txt

    kdialog --textbox .tableNames.txt 280 320
    rm .tableNames.txt
}

dropTable() {
    checkIfTableExists "$db_name"

    table_choice=$(kdialog --menu "Select a Table to Drop" "${table_menu[@]}")

    if [ -n "$table_choice" ]; then
        selected_table="$(echo "$tables" | sed -n "${table_choice}p")"
        if kdialog --yesno "Are you sure you want to delete '$selected_table'?"; then
            rm "$table_dir/$selected_table.table"
            rm "$table_dir/$selected_table.meta"
            kdialog --msgbox "Table '$selected_table' deleted successfully."
        fi
    fi
}

insertIntoTable() {
    checkIfTableExists "$db_name"

    table_choice=$(kdialog --menu "Select a table to insert data into:" "${table_menu[@]}")
    [ -z "$table_choice" ] && return

    selected_table="$(echo "$tables" | sed -n "${table_choice}p")"

    metadata_file="$table_dir/$selected_table.meta"
    table_file="$table_dir/$selected_table.table"

    [ ! -f "$metadata_file" ] && kdialog --sorry "Metadata file not found for table '$selected_table'." && return

    # Read column names and types
    columns=()
    col_types=()
    col_defs=()
    pk_index=-1 # Track the index of the Primary Key column

    IFS='|' read -ra metadata_array <"$metadata_file"

    for i in "${!metadata_array[@]}"; do
        IFS=':' read -r col_name col_type is_pk <<<"${metadata_array[$i]}"
        if [ -n "$col_name" ]; then
            columns+=("$col_name")
            col_types+=("$col_type")
            col_defs+=("$col_name:$col_type:$is_pk")
            [ "$is_pk" == "PK" ] && pk_index=$i
        fi
    done

    [ ${#columns[@]} -eq 0 ] && kdialog --sorry "No columns found in metadata." && return

    # Collect user input for each column
    row_data=()
    for i in "${!columns[@]}"; do
        col_name="${columns[$i]}"
        col_type="${col_types[$i]}"
        is_pk="${col_defs[$i]##*:}"

        # Inside insertIntoTable() function, modify the hint message:
        while true; do
            hint="Enter value for $col_name"
            [ "$col_type" == "1" ] && hint+="\n[Type: Integer]"
            [ "$col_type" == "2" ] && hint+="\n[Type: String]"
            [ "$is_pk" == "PK" ] && hint+="\n[Primary Key - Must be Unique && Not Empty]" || hint+="\n(Press Enter for NULL)"

            value=$(kdialog --inputbox "$hint")
            [ $? -ne 0 ] && return

            # Handle NULL values
            if [ -z "$value" ]; then
                [[ "$is_pk" == "PK" ]] && kdialog --sorry "Primary Key cannot be empty." && continue
                row_data+=("NULL")
                break
            fi

            # Validate integer input (col_type == "1" means it's an integer)
            [[ "$col_type" == "1" && ! "$value" =~ ^[0-9]+$ ]] && kdialog --sorry "Invalid integer." && continue

            # Validate string input (col_type == "2" means it's a string)
            [[ "$col_type" == "2" && "$value" == *"|"* ]] && kdialog --sorry "Invalid input for $col_name. The '|' character is not allowed." && continue

            # Check PK Uniqueness
            if [ "$is_pk" == "PK" ]; then
                if grep -q "^$value|" "$table_file"; then
                    kdialog --sorry "Error: Primary key '$value' already exists in table '$selected_table'."
                    continue
                fi
            fi

            row_data+=("$value")
            break
        done
    done

    # Insert data into table (separating values with '|')
    printf "%s\n" "$(IFS="|"; echo "${row_data[*]}")" >>"$table_file"

    kdialog --msgbox "Data inserted successfully into '$selected_table'."
}

selectFromTable() {
    checkIfTableExists "$db_name"

    table_choice=$(kdialog --menu "Select a table to query:" "${table_menu[@]}")

    [ -z "$table_choice" ] && return

    selected_table="$(echo "$tables" | sed -n "${table_choice}p")"
    table_file="$table_dir/$selected_table.table"
    metadata_file="$table_dir/$selected_table.meta"

    IFS='|' read -ra headers <"$metadata_file"

    format_table_output() {
        local data="$1"
        local -a column_widths

        # Determine column widths
        while IFS='|' read -r line; do
            IFS='|' read -ra values <<<"$line"
            for i in "${!values[@]}"; do
                len=${#values[$i]}
                ((len > column_widths[i])) && column_widths[i]=$len
            done
        done <<<"$data"

        # Ensure column headers count towards max width
        for i in "${!headers[@]}"; do
            col_name="${headers[$i]%%:*}"
            ((${#col_name} > column_widths[i])) && column_widths[i]=${#col_name}
        done

        # Create formatted separator
        separator="+"
        for width in "${column_widths[@]}"; do
            separator+="$(printf '%*s' "$((width + 2))" | tr ' ' '-')+"
        done

        # Build the header row
        header_row="|"
        for i in "${!headers[@]}"; do
            col_name="${headers[$i]%%:*}"
            header_row+=" $(printf "%-${column_widths[i]}s" "$col_name") |"
        done

        # Format data rows
        output="${separator}\n${header_row}\n${separator}\n"
        while IFS='|' read -r line; do
            row="|"
            IFS='|' read -ra values <<<"$line"
            for i in "${!values[@]}"; do
                row+=" $(printf "%-${column_widths[i]}s" "${values[$i]}") |"
            done
            output+="${row}\n"
        done <<<"$data"

        output+="${separator}\n"
        echo -e "$output"
    }

    select_choice=$(kdialog --menu "Select Query Type" \
        1 "Show all records" \
        2 "Find a value")

    case "$select_choice" in
    1)
        # Show all records
        [ ! -s "$table_file" ] && kdialog --sorry "Table '$selected_table' is empty." && return
        formatted_output=$(format_table_output "$(cat "$table_file")")
        kdialog --msgbox "<pre>${formatted_output}</pre>" --ok-label "done"
        ;;

    2)
        # Get search value from user
        search_value=$(kdialog --inputbox "Enter search value:")
        [ $? -ne 0 ] && return

        search_result=$(grep -i "$search_value" "$table_file")
        if [ -z "$search_result" ]; then
            kdialog --sorry "No records found matching '$search_value'"
        else
            formatted_output=$(format_table_output "$search_result")
            kdialog --msgbox "<pre>${formatted_output}</pre>" --ok-label "done"
        fi
        ;;

    *)
        return
        ;;
    esac
}

deleteFromTable() {
    checkIfTableExists "$db_name"

    table_choice=$(kdialog --menu "Select a table to delete from:" "${table_menu[@]}")
    [ -z "$table_choice" ] && return

    selected_table="$(echo "$tables" | sed -n "${table_choice}p")"
    table_file="$table_dir/$selected_table.table"
    metadata_file="$table_dir/$selected_table.meta"

    # Check if table is empty
    if [ ! -s "$table_file" ]; then
        kdialog --sorry "Table '$selected_table' is empty."
        return
    fi

    # Get delete method choice
    delete_choice=$(kdialog --menu "Select Delete Method:" \
        1 "Delete by Primary Key" \
        2 "Delete by Search Value")
    [ -z "$delete_choice" ] && return

    case "$delete_choice" in

    1)
        # Delete by Primary Key
        # Find primary key column name and index
        pk_col=""
        pk_index=0
        IFS='|' read -ra metadata_array <"$metadata_file"
        for i in "${!metadata_array[@]}"; do
            IFS=':' read -r col_name _ is_pk <<<"${metadata_array[$i]}"
            if [ "$is_pk" == "PK" ]; then
                pk_col="$col_name"
                pk_index=$i
                break
            fi
        done

        if [ -z "$pk_col" ]; then
            kdialog --sorry "No primary key found in table '$selected_table'."
            return
        fi

        # Get PK value from user
        pk_value=$(kdialog --inputbox "Enter Primary Key value to delete:")
        [ $? -ne 0 ] && return

        # Create temporary file
        temp_file=$(mktemp)
        deleted=false

        # Search and delete matching row
        while IFS='|' read -r line || [ -n "$line" ]; do
            row_pk=$(echo "$line" | cut -d'|' -f$((pk_index + 1)))
            if [ "$row_pk" != "$pk_value" ]; then
                echo "$line" >>"$temp_file"
            else
                deleted=true
            fi
        done <"$table_file"

        if [ "$deleted" = true ]; then
            mv "$temp_file" "$table_file"
            kdialog --msgbox "Record with Primary Key '$pk_value' deleted successfully."
        else
            rm "$temp_file"
            kdialog --sorry "No record found with Primary Key '$pk_value'."
        fi
        ;;

    2)
        # Delete by Search Value
        search_value=$(kdialog --inputbox "Enter value to search and delete:")
        [ $? -ne 0 ] && return

        # Create temporary file
        temp_file=$(mktemp)
        deleted=false

        # Search and delete matching rows
        while IFS= read -r line || [ -n "$line" ]; do
            if ! echo "$line" | grep -qi "$search_value"; then
                echo "$line" >>"$temp_file"
            else
                deleted=true
            fi
        done <"$table_file"

        if [ "$deleted" = true ]; then
            mv "$temp_file" "$table_file"
            kdialog --msgbox "Records containing '$search_value' deleted successfully."
        else
            rm "$temp_file"
            kdialog --sorry "No records found containing '$search_value'."
        fi
        ;;

    *)
        return
        ;;
    esac
}

updateTable() {
    checkIfTableExists "$db_name"

    table_choice=$(kdialog --menu "Select a table to update:" "${table_menu[@]}")
    [ -z "$table_choice" ] && return

    selected_table="$(echo "$tables" | sed -n "${table_choice}p")"
    table_file="$table_dir/$selected_table.table"
    metadata_file="$table_dir/$selected_table.meta"

    # Check if table is empty
    if [ ! -s "$table_file" ]; then
        kdialog --sorry "Table '$selected_table' is empty."
        return
    fi

    # Find primary key column name and index
    pk_col=""
    pk_index=0
    IFS='|' read -ra metadata_array <"$metadata_file"
    for i in "${!metadata_array[@]}"; do
        IFS=':' read -r col_name col_type is_pk <<<"${metadata_array[$i]}"
        if [ "$is_pk" == "PK" ]; then
            pk_col="$col_name"
            pk_index=$i
            break
        fi
    done

    if [ -z "$pk_col" ]; then
        kdialog --sorry "No primary key found in table '$selected_table'."
        return
    fi

    # Get PK value from user
    pk_value=$(kdialog --inputbox "Enter Primary Key value to update:")
    [ $? -ne 0 ] && return

    # Find the record with the given PK
    record=""
    while IFS= read -r line; do
        row_pk=$(echo "$line" | cut -d'|' -f$((pk_index + 1)))
        if [ "$row_pk" = "$pk_value" ]; then
            record="$line"
            break
        fi
    done <"$table_file"

    if [ -z "$record" ]; then
        kdialog --sorry "No record found with Primary Key '$pk_value'."
        return
    fi

    # Create arrays to store column info and current values
    IFS='|' read -ra current_values <<<"$record"
    columns=()
    col_types=()

    # Read metadata for column names and types
    for meta in "${metadata_array[@]}"; do
        IFS=':' read -r col_name col_type _ <<<"$meta"
        columns+=("$col_name")
        col_types+=("$col_type")
    done

    # Create temporary file for the updated data
    temp_file=$(mktemp)
    updated=false

    # Process each line in the table
    while IFS= read -r line; do
        row_pk=$(echo "$line" | cut -d'|' -f$((pk_index + 1)))
        if [ "$row_pk" = "$pk_value" ]; then
            # This is the row to update
            new_values=()

            # Get new values for each column
            for i in "${!columns[@]}"; do
                col_name="${columns[$i]}"
                col_type="${col_types[$i]}"
                current_value="${current_values[$i]}"

                while true; do
                    hint="Update value for $col_name\nCurrent value: $current_value"
                    [ "$col_type" == "1" ] && hint+="\n[Type: Integer]"
                    [ "$col_type" == "2" ] && hint+="\n[Type: String]"
                    [ "$i" == "$pk_index" ] && hint+="\n[Primary Key - Must be Unique]"
                    hint+="\n(Press Enter to keep current value)"

                    new_value=$(kdialog --inputbox "$hint")
                    [ $? -ne 0 ] && rm "$temp_file" && return

                    # If empty, keep current value
                    if [ -z "$new_value" ]; then
                        new_value="$current_value"
                        break
                    fi

                    # Validate integer input
                    if [ "$col_type" == "1" ] && ! [[ "$new_value" =~ ^[0-9]+$ ]]; then
                        kdialog --sorry "Invalid integer."
                        continue
                    fi

                    # Validate string input
                    if [ "$col_type" == "2" ] && [[ "$new_value" == *"|"* ]]; then
                        kdialog --sorry "The '|' character is not allowed."
                        continue
                    fi

                    # Check PK uniqueness if updating PK
                    if [ "$i" == "$pk_index" ] && [ "$new_value" != "$current_value" ]; then
                        if grep -q "^$new_value|" "$table_file" || grep -q "|$new_value|" "$table_file"; then
                            kdialog --sorry "Error: Primary key '$new_value' already exists."
                            continue
                        fi
                    fi

                    break
                done

                new_values+=("$new_value")
                [ "$new_value" != "$current_value" ] && updated=true
            done

            # Write updated record
            printf "%s\n" "$(
                IFS="|"
                echo "${new_values[*]}"
            )" >>"$temp_file"
        else
            # Write unchanged record
            echo "$line" >>"$temp_file"
        fi
    done <"$table_file"

    if [ "$updated" = true ]; then
        mv "$temp_file" "$table_file"
        kdialog --msgbox "Record updated successfully."
    else
        rm "$temp_file"
        kdialog --msgbox "No changes made to the record."
    fi
}
