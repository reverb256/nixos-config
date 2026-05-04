#!/usr/bin/env python3
"""
Comprehensive benchmark for 3 llama-server models
Uses curl for HTTP requests
"""

import time
import json
import subprocess
import sys
from typing import Dict, Tuple
from datetime import datetime

# Model endpoints
MODELS = {
    "35B-Qwen3.6": {"host": "zephyr", "port": 1235},
    "9B-Qwen3.5": {"host": "zephyr", "port": 1236},
    "4B-Qwen3.5": {"host": "sentry", "port": 1235},
}

# Test cases
TESTS = {
    "gen_speed_off": {
        "prompt": "Write a short paragraph about artificial intelligence.",
        "max_tokens": 200,
        "temperature": 0.3,
        "enable_thinking": False,
        "expected_type": "text"
    },
    "gen_speed_on": {
        "prompt": "Write a short paragraph about artificial intelligence.",
        "max_tokens": 200,
        "temperature": 0.3,
        "enable_thinking": True,
        "expected_type": "text"
    },
    "qa_accuracy": {
        "prompt": "What is capital of Australia? One word.",
        "max_tokens": 50,
        "temperature": 0.3,
        "enable_thinking": False,
        "expected_answer": "Canberra",
        "check_contains": True
    },
    "code_generation": {
        "prompt": "Write a Python function fibonacci(n) that returns the nth Fibonacci number.",
        "max_tokens": 150,
        "temperature": 0.3,
        "enable_thinking": False,
        "expected_type": "code",
        "check_keywords": ["def fibonacci", "return"]
    },
    "math_problem": {
        "prompt": "I have 3 apples, give 1 to Bob, buy 5 more, eat 2. How many left? Show your work.",
        "max_tokens": 200,
        "temperature": 0.3,
        "enable_thinking": True,
        "expected_answer": "5",
        "check_contains": True
    }
}

def make_request(host: str, port: int, prompt: str, max_tokens: int, 
                  temperature: float, enable_thinking: bool) -> Dict:
    """
    Make streaming request using curl and measure timing
    """
    url = f"http://{host}:{port}/v1/chat/completions"
    
    chat_template_kwargs = {"enable_thinking": enable_thinking} if not enable_thinking else {}
    
    payload = {
        "model": "model",
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": temperature,
        "stream": True,
        "chat_template_kwargs": chat_template_kwargs
    }
    
    # Build curl command
    curl_cmd = [
        "curl", "-s", "-X", "POST", url,
        "-H", "Content-Type: application/json",
        "-d", json.dumps(payload),
        "--no-buffer",
        "--connect-timeout", "30",
        "--max-time", "60"
    ]
    
    start_time = time.time()
    first_token_time = None
    full_content = ""
    reasoning_content = ""
    token_count = 0
    
    try:
        # Start the process
        process = subprocess.Popen(curl_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, 
                                   text=True, bufsize=1)
        
        prompt_time = time.time() - start_time
        
        # Read streaming output line by line
        for line in process.stdout:
            line = line.strip()
            if line.startswith('data: '):
                data_str = line[6:]
                if data_str == '[DONE]':
                    break
                try:
                    data = json.loads(data_str)
                    if 'choices' in data and len(data['choices']) > 0:
                        delta = data['choices'][0].get('delta', {})
                        content = delta.get('content', '')
                        reasoning = delta.get('reasoning_content', '')
                        if first_token_time is None and (content or reasoning):
                            first_token_time = time.time()
                        if content:
                            full_content += content
                            token_count += 1
                        if reasoning:
                            reasoning_content += reasoning
                except json.JSONDecodeError:
                    pass
        
        gen_time = (time.time() - first_token_time) if first_token_time else 0
        process.wait(timeout=5)
        
        return {
            "prompt_time": prompt_time,
            "gen_time": gen_time,
            "ttft": (first_token_time - start_time) if first_token_time else -1,
            "content": full_content,
            "reasoning_content": reasoning_content,
            "token_count": token_count,
            "reasoning_token_count": len(reasoning_content.split()) if reasoning_content else 0,
            "success": True
        }
    except Exception as e:
        return {
            "prompt_time": 0,
            "gen_time": 0,
            "ttft": 0,
            "content": "",
            "reasoning_content": "",
            "token_count": 0,
            "reasoning_token_count": 0,
            "success": False,
            "error": str(e)
        }

def estimate_tokens(text: str) -> int:
    """Rough token estimation (approx 4 chars per token)"""
    return len(text) // 4

def check_accuracy(test_name: str, content: str, test_config: Dict) -> Tuple[bool, str]:
    """Check if answer is correct"""
    content = content.strip().lower()
    
    if "expected_answer" in test_config:
        expected = test_config["expected_answer"].lower()
        if test_config.get("check_contains", False):
            return expected in content, f"Expected '{expected}' in response"
        else:
            return expected == content, f"Expected '{expected}'"
    
    if test_config.get("check_keywords"):
        keywords = test_config["check_keywords"]
        missing = [kw for kw in keywords if kw.lower() not in content]
        if missing:
            return False, f"Missing keywords: {missing}"
        return True, "All keywords found"
    
    return True, "No specific accuracy check"

def run_benchmark():
    """Run comprehensive benchmark on all models"""
    results = {}
    
    print("=" * 80)
    print("COMPREHENSIVE LLAMA-SERVER BENCHMARK")
    print("=" * 80)
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print()
    
    for model_name, model_info in MODELS.items():
        host = model_info["host"]
        port = model_info["port"]
        
        print(f"\n{'=' * 80}")
        print(f"BENCHMARKING MODEL: {model_name}")
        print(f"Endpoint: {host}:{port}")
        print(f"{'=' * 80}\n")
        
        model_results = {}
        
        for test_name, test_config in TESTS.items():
            print(f"Test: {test_name}")
            print(f"  Prompt: {test_config['prompt'][:60]}...")
            print(f"  Thinking: {'ON' if test_config['enable_thinking'] else 'OFF'}")
            sys.stdout.flush()
            
            result = make_request(
                host=host,
                port=port,
                prompt=test_config["prompt"],
                max_tokens=test_config["max_tokens"],
                temperature=test_config["temperature"],
                enable_thinking=test_config["enable_thinking"]
            )
            
            if not result["success"]:
                print(f"  ERROR: {result.get('error', 'Unknown error')}")
                model_results[test_name] = result
                print()
                continue
            
            # Calculate metrics
            prompt_tokens = estimate_tokens(test_config["prompt"])
            gen_speed = result["token_count"] / result["gen_time"] if result["gen_time"] > 0 else 0
            prompt_speed = prompt_tokens / result["prompt_time"] if result["prompt_time"] > 0 else 0
            
            # Check accuracy
            is_correct, accuracy_msg = check_accuracy(test_name, result["content"], test_config)
            
            result["prompt_tokens"] = prompt_tokens
            result["gen_speed"] = gen_speed
            result["prompt_speed"] = prompt_speed
            result["is_correct"] = is_correct
            result["accuracy_msg"] = accuracy_msg
            
            print(f"  TTFT: {result['ttft']*1000:.1f}ms")
            print(f"  Prompt time: {result['prompt_time']:.3f}s")
            print(f"  Gen time: {result['gen_time']:.3f}s")
            print(f"  Tokens generated: {result['token_count']}")
            print(f"  Gen speed: {gen_speed:.1f} tokens/s")
            print(f"  Prompt speed: {prompt_speed:.1f} tokens/s")
            print(f"  Reasoning tokens: {result['reasoning_token_count']}")
            print(f"  Correct: {is_correct} ({accuracy_msg})")
            if result["content"]:
                print(f"  Content preview: {result['content'][:100]}...")
            
            model_results[test_name] = result
            print()
        
        results[model_name] = model_results
    
    # Print summary table
    print("\n" + "=" * 80)
    print("SUMMARY TABLE")
    print("=" * 80)
    
    header = f"{'Model':<15} {'Test':<20} {'TTFT(ms)':<10} {'Gen(t/s)':<10} {'Prompt(t/s)':<12} {'Correct':<8} {'Reasoning':<10}"
    print(header)
    print("-" * 100)
    
    for model_name, model_results in results.items():
        for test_name, result in model_results.items():
            if result["success"]:
                row = f"{model_name:<15} {test_name:<20} {result['ttft']*1000:<10.1f} {result['gen_speed']:<10.1f} {result['prompt_speed']:<12.1f} {str(result['is_correct']):<8} {result['reasoning_token_count']:<10}"
            else:
                row = f"{model_name:<15} {test_name:<20} {'ERROR':<10} {'ERROR':<10} {'ERROR':<12} {'N/A':<8} {'N/A':<10}"
            print(row)
    
    # Calculate scores
    print("\n" + "=" * 80)
    print("QUALITY SCORES")
    print("=" * 80)
    
    for model_name, model_results in results.items():
        correct_count = sum(1 for r in model_results.values() if r.get("is_correct", False))
        total_tests = sum(1 for r in model_results.values() if r["success"])
        avg_gen_speed = sum(r.get("gen_speed", 0) for r in model_results.values() if r["success"]) / total_tests if total_tests > 0 else 0
        avg_ttft = sum(r.get("ttft", 0) for r in model_results.values() if r["success"]) / total_tests if total_tests > 0 else 0
        
        score = (correct_count / total_tests * 100) if total_tests > 0 else 0
        speed_tier = "Fast" if avg_gen_speed > 50 else "Medium" if avg_gen_speed > 20 else "Slow"
        
        print(f"\n{model_name}:")
        print(f"  Accuracy: {correct_count}/{total_tests} ({score:.1f}%)")
        print(f"  Avg Gen Speed: {avg_gen_speed:.1f} tokens/s")
        print(f"  Avg TTFT: {avg_ttft*1000:.1f}ms")
        print(f"  Speed Tier: {speed_tier}")
    
    # Save results to JSON
    output_file = "/etc/nixos/benchmark_results.json"
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\nResults saved to: {output_file}")
    print(f"\nBenchmark completed: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    return results

if __name__ == "__main__":
    results = run_benchmark()
