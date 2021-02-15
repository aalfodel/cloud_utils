#!/usr/bin/env bash


# TODO
# * add "set -euo pipefail"
# * delete, at the end, the downloaded files (ex. from "curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh")
# * add more "systemctl status" for checking


# NOTE GCE startup scripts are executed every time the instance boots up.
# **WARNING** It will take a while between the instance bootstrap completition and the
#             execution of all the following operations.
#             You can monitor the script by sshing into the instance and then executing:
#             sudo journalctl -u google-startup-scripts.service -f

# NOTE
# **WARNING** This script has been tested only on CentOS 8


# config for echo pretty print
SCRIPTNAME="[$(basename $0 .sh)]"

echo "$SCRIPTNAME START"

# Install Logging Agent
echo "$SCRIPTNAME Checking Stackdriver Logging Agent"
if [ -n "$(sudo systemctl list-unit-files | grep google-fluentd)" ]; then
    echo "$SCRIPTNAME Stackdriver Logging Agent is already installed"
else
    echo "$SCRIPTNAME Installing Stackdriver Logging Agent"
    curl -sSO https://dl.google.com/cloudagents/add-logging-agent-repo.sh
    sudo bash add-logging-agent-repo.sh
    sudo dnf install -y google-fluentd-1.* google-fluentd-catch-all-config-structured
    sudo systemctl enable google-fluentd
    sudo systemctl start google-fluentd
fi

# Install Monitoring Agent
echo "$SCRIPTNAME Checking Stackdriver Monitoring Agent"
if [ -n "$(sudo systemctl list-unit-files | grep stackdriver-agent)" ]; then
    echo "$SCRIPTNAME Stackdriver Monitoring Agent is already installed"
else
    echo "$SCRIPTNAME Installing Stackdriver Monitoring Agent"
    curl -sSO https://dl.google.com/cloudagents/add-monitoring-agent-repo.sh
    sudo bash add-monitoring-agent-repo.sh
    sudo dnf install -y stackdriver-agent-6.*
    sudo systemctl enable stackdriver-agent
    sudo systemctl start stackdriver-agent
fi

# Add auditd logs to Logging Agent configuration
AUDITD_LOG_CONF_PATH="/etc/google-fluentd/config.d/auditd.conf"
echo "$SCRIPTNAME Checking auditd logs configuration for Logging Agent"
if [ -f "$AUDITD_LOG_CONF_PATH" ] && [ -s "$AUDITD_LOG_CONF_PATH" ]; then
    echo "$SCRIPTNAME Auditd logs configuration for Logging Agent already installed"
else
    echo "$SCRIPTNAME Adding auditd logs to Logging Agent configuration ($AUDITD_LOG_CONF_PATH)"
    sudo cat <<-EOF | sudo tee "$AUDITD_LOG_CONF_PATH"
    <source>
        @type tail
        format none
        path /var/log/audit/audit.log
        pos_file /var/lib/google-fluentd/pos/audit.pos
        read_from_head true
        tag auditd
    </source>
EOF
    sudo systemctl restart google-fluentd
fi

# Fix Monitoring Agent logs spam
# (see https://myshittycode.com/2020/06/13/gcp-stackdriver-agent-write_gcm-can-not-take-infinite-value-error/)
COLLECTD_CONF_PATH="/etc/stackdriver/collectd.conf"
echo "$SCRIPTNAME Checking Monitoring Agent logs spam fix"
if [ -f "$COLLECTD_CONF_PATH" ] && [ -z "$(sudo grep 'LoadPlugin swap' $COLLECTD_CONF_PATH)" ]; then
    echo "$SCRIPTNAME Stackdriver Monitoring Agent logs spam already fixed"
elif [ -f "$COLLECTD_CONF_PATH" ]; then
    echo "$SCRIPTNAME Fixing Monitoring Agent logs spam"
    sudo sed -i '/LoadPlugin swap/,+3d' "$COLLECTD_CONF_PATH"
    sudo systemctl restart stackdriver-agent
else
    echo "$SCRIPTNAME \"$COLLECTD_CONF_PATH\" not found"
fi

echo "$SCRIPTNAME END"
