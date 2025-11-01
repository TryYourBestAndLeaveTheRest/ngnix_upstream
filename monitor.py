# https://hooks.slack.com/triggers/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


import time

log_file = 'access.log'

def monitor_logs():
    try:
        with open(log_file, 'r') as file:
            # Go to the end of the file (like tail -f)
            file.seek(0, 2)
            
            while True:
                line = file.readline()
                if line:
                    process_log_line(line)
                else:
                    time.sleep(0.1)

    except Exception as e:
        print(f"Error monitoring logs: {e}")

def process_log_line(line):
    # Example of parsing a log line (make sure to adjust for your format)
    # Extract the upstream server address and status code
    parts = line.split()
    upstream_addr = parts[-1]  # Assuming this is the last part of the log line
    status_code = parts[8]     # Assuming the status code is in this position
    
    # Add logic for detecting failovers or error rates
    if status_code.startswith('5'):  # 5xx errors
        print(f"Error detected: {line}")
        send_alert_to_slack(line)  # Send alert if there's a 5xx error

def send_alert_to_slack(message):
    # Code to send the alert to Slack
    print(f"Sending alert to Slack: {message}")
    pass

if __name__ == "__main__":
    monitor_logs()
