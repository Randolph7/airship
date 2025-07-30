def log_token_speed(model_name, total_tokens, elapsed, tokens_per_sec, log_tag=""):
    with open("log/token_speed_log.txt", "a", encoding="utf-8") as f:
        tag_str = f"[{log_tag}]" if log_tag else ""
        f.write(
            f"{tag_str}Model: {model_name}, tokens: {total_tokens}, time: {elapsed:.2f}second, token/s: {tokens_per_sec:.2f}\n"
        )

if __name__ == "__main__":
    # 用于测试
    log_token_speed("gpt-4o", 100, 2.5, 40, log_tag="normal")
    log_token_speed("gpt-4o", 120, 3.0, 40, log_tag="replan") 