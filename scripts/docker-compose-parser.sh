#!/bin/bash

# Docker Compose Parser for Port Detection
# Part of BranchBox Port Doctor system

set -e

# Parse docker-compose files to find hardcoded ports that will conflict
parse_hardcoded_ports() {
    local compose_file=$1
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    
    # Extract hardcoded port mappings (e.g., "8080:8080", "3000:3000")
    # This regex matches common port mapping patterns:
    # - "port:port" (quoted)
    # - port:port (unquoted)
    # - - "port:port" (array syntax)
    grep -E '^[[:space:]]*-[[:space:]]*"?[0-9]+:[0-9]+"?' "$compose_file" | \
    sed -E 's/^[[:space:]]*-[[:space:]]*"?([0-9]+):([0-9]+)"?.*$/\1:\2/' | \
    sort -u
}

# Extract service names that have hardcoded ports
get_services_with_hardcoded_ports() {
    local compose_file=$1
    local current_service=""
    local in_ports_section=false
    local in_services_section=false
    local service_reported=false
    
    if [ ! -f "$compose_file" ]; then
        return 1
    fi
    
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            continue
        fi
        
        # Detect the services section
        if [[ "$line" =~ ^services:[[:space:]]*$ ]]; then
            in_services_section=true
            current_service=""
            in_ports_section=false
            continue
        fi
        
        # Exit services section if we hit a top-level key
        if [[ "$line" =~ ^[a-zA-Z] ]] && [[ ! "$line" =~ ^services: ]]; then
            in_services_section=false
            continue
        fi
        
        # Only process lines within the services section
        if [ "$in_services_section" = false ]; then
            continue
        fi
        
        # Detect service definitions (2-space indented under services)
        if [[ "$line" =~ ^[[:space:]]{2}([a-zA-Z0-9_-]+):[[:space:]]*$ ]]; then
            current_service="${BASH_REMATCH[1]}"
            in_ports_section=false  # New service = exit ports section
            service_reported=false
            continue
        fi
        
        # Detect ports section within a service (4-space indented)
        if [[ "$line" =~ ^[[:space:]]{4}ports:[[:space:]]*$ ]]; then
            in_ports_section=true
            continue
        fi
        
        # Reset ports section when we hit another service property at same level
        if [[ "$line" =~ ^[[:space:]]{4}[a-zA-Z_-]+:[[:space:]] ]] && [[ ! "$line" =~ ports: ]]; then
            in_ports_section=false
            continue
        fi
        
        # If we're in a ports section and find hardcoded ports, record the service
        if [ "$in_ports_section" = true ] && [ "$service_reported" = false ] && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*\"?[0-9]+:[0-9]+\"? ]]; then
            echo "$current_service"
            service_reported=true
        fi
        
    done < "$compose_file" | sort -u
}

# Extract the host port from a port mapping (e.g., "8080:8080" -> "8080")
extract_host_port() {
    local port_mapping=$1
    echo "$port_mapping" | cut -d':' -f1
}

# Extract the container port from a port mapping (e.g., "8080:8080" -> "8080")  
extract_container_port() {
    local port_mapping=$1
    echo "$port_mapping" | cut -d':' -f2
}

# Check if a compose file has any hardcoded ports
has_hardcoded_ports() {
    local compose_file=$1
    local ports=$(parse_hardcoded_ports "$compose_file")
    [ -n "$ports" ]
}

# Get port range for a given base port (for smart assignment)
get_port_range() {
    local port=$1
    
    case "$port" in
        80[0-9][0-9])   echo "8000-8999" ;;  # Web services
        30[0-9][0-9])   echo "3000-3999" ;;  # Frontend services  
        50[0-9][0-9])   echo "5000-5999" ;;  # Database services
        60[0-9][0-9])   echo "6000-6999" ;;  # Cache services
        90[0-9][0-9])   echo "9000-9999" ;;  # Monitoring services
        *)              echo "$((port))-$((port + 999))" ;; # Default: +1000 range
    esac
}

# Main function for CLI usage
main() {
    local compose_file="${1:-docker-compose.yml}"
    local action="${2:-detect}"
    
    case "$action" in
        detect|ports)
            parse_hardcoded_ports "$compose_file"
            ;;
        services)
            get_services_with_hardcoded_ports "$compose_file"
            ;;
        check)
            if has_hardcoded_ports "$compose_file"; then
                echo "Hardcoded ports detected"
                exit 0
            else
                echo "No hardcoded ports found"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 [compose-file] [detect|services|check]"
            echo ""
            echo "Actions:"
            echo "  detect  - List all hardcoded port mappings (default)"
            echo "  services - List services with hardcoded ports"
            echo "  check   - Check if any hardcoded ports exist"
            exit 1
            ;;
    esac
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi