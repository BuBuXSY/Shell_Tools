#!/usr/bin/env bats

setup() {
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
}

@test "certificate deployment rejects stale Nginx paths" {
    run bash -c '
        source "$1/install_cert.sh"
        LOG_FILE=/dev/null
        nginx() { printf "ssl_certificate /etc/nginx/cert_file/fullchain.pem;\nssl_certificate_key /etc/nginx/cert_file/key.pem;\n"; }
        verify_nginx_certificate_deployment /etc/nginx/ssl/new.fullchain.pem /etc/nginx/ssl/new.key.pem
    ' _ "$REPO_ROOT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"没有引用刚部署的证书"* ]]
}

@test "certificate deployment requires exact paths" {
    run bash -c '
        source "$1/install_cert.sh"
        LOG_FILE=/dev/null
        nginx() { printf "ssl_certificate /etc/nginx/ssl/new.fullchain.pem.old;\nssl_certificate_key /etc/nginx/ssl/new.key.pem.old;\n"; }
        verify_nginx_certificate_deployment /etc/nginx/ssl/new.fullchain.pem /etc/nginx/ssl/new.key.pem
    ' _ "$REPO_ROOT"
    [ "$status" -eq 1 ]
}

@test "certificate deployment accepts active Nginx paths" {
    run bash -c '
        source "$1/install_cert.sh"
        LOG_FILE=/dev/null
        nginx() { printf "ssl_certificate     /etc/nginx/ssl/new.fullchain.pem;\nssl_certificate_key /etc/nginx/ssl/new.key.pem;\n"; }
        verify_nginx_certificate_deployment /etc/nginx/ssl/new.fullchain.pem /etc/nginx/ssl/new.key.pem
    ' _ "$REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"已引用新证书"* ]]
}
