def release_sort_key(text):
    nums = [int(x) for x in re.findall(r"\d+", str(text))]
    return nums


