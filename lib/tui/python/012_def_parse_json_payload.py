def parse_json_payload(text):
    body = (text or "").strip()
    if not body:
        return {}
    return json.loads(body)


