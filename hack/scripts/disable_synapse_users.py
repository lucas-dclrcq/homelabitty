import time

import requests

token = "token"
synapse_base_url = "https://matrix.url"

synapse_user_ids = [
]


def disable_user(user_id):
    rebuild = f"{synapse_base_url}/_synapse/admin/v1/deactivate/{user_id}"
    headers = {
        'Content-Type': "application/json",
        'Authorization': f"Bearer {token}",
    }

    response = requests.post(rebuild, headers=headers, timeout=50000)
    return response


print(f"{len(synapse_user_ids)} users")
print("--------------------------------------------")
current_user = 1

for synapse_user_id in synapse_user_ids:
    print(f"Disabling account for user {synapse_user_id} ({current_user}/{len(synapse_user_ids)})")

    start = time.time()
    result = disable_user(synapse_user_id)
    end = time.time()

    roundedElapsedTime = round(end - start, 2)

    if 200 <= result.status_code < 300:
        print(f"Successfully disabled user {synapse_user_id} in {roundedElapsedTime}s")
    elif result.status_code == 504:
        print(f"Timeout for user {synapse_user_id} in {roundedElapsedTime}s but it's ok")
    else:
        print(
            f"Failed to disable user {synapse_user_id} with status code {result.status_code} in {roundedElapsedTime}s")
        break

    current_user += 1
    print("\n")
