"""
Load Testing Script for CS6650 Homework 10
Tests checkout flow: Create Cart -> Add Item -> Checkout
Sends 200k checkout messages to the Application Load Balancer
"""

import requests
import threading
import time
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from collections import defaultdict
import argparse
import sys

# Configuration
DEFAULT_ALB_URL = "http://cs6650-hw10-alb-1645005431.us-west-2.elb.amazonaws.com"
DEFAULT_TOTAL_REQUESTS = 200000
DEFAULT_THREAD_COUNTS = [10, 20, 50, 100, 200]

# Global statistics
stats_lock = threading.Lock()
stats = {
    'total_requests': 0,
    'successful': 0,
    'failed': 0,
    'payment_declined': 0,
    'errors': defaultdict(int),
    'start_time': None,
    'end_time': None
}


def checkout_flow(alb_url, request_id):
    """
    Single checkout flow: create cart -> add item -> checkout
    Uses Session to maintain cookies for sticky sessions
    Returns: (success: bool, error_type: str)
    """
    # Use Session to maintain cookies (for sticky sessions)
    session = requests.Session()
    
    try:
        # Step 1: Create shopping cart
        cart_resp = session.post(
            f"{alb_url}/shopping-carts",
            json={"customer_id": f"CUST-{request_id}"},
            timeout=30
        )
        
        if cart_resp.status_code != 201:
            return False, f"cart_creation_{cart_resp.status_code}"
        
        cart_data = cart_resp.json()
        cart_id = cart_data.get("cart_id")
        if not cart_id:
            return False, "cart_id_missing"
        
        # Step 2: Add item to cart (same session = same cookie = same instance)
        add_item_resp = session.post(
            f"{alb_url}/shopping-carts/{cart_id}/items",
            json={"product_id": f"PROD-{request_id % 1000}", "quantity": 1},
            timeout=30
        )
        
        if add_item_resp.status_code != 200:
            return False, f"add_item_{add_item_resp.status_code}"
        
        # Step 3: Checkout (same session = same cookie = same instance)
        checkout_resp = session.post(
            f"{alb_url}/shopping-carts/{cart_id}/checkout",
            json={"credit_card_number": "1234-5678-9012-3456"},
            timeout=30
        )
        
        if checkout_resp.status_code == 200:
            return True, "success"
        elif checkout_resp.status_code == 402:
            return False, "payment_declined"
        else:
            return False, f"checkout_{checkout_resp.status_code}"
            
    except requests.exceptions.Timeout:
        return False, "timeout"
    except requests.exceptions.ConnectionError:
        return False, "connection_error"
    except Exception as e:
        return False, f"exception_{type(e).__name__}"
    finally:
        session.close()


def worker_thread(alb_url, request_id):
    """Worker function for a single request"""
    success, error_type = checkout_flow(alb_url, request_id)
    
    with stats_lock:
        stats['total_requests'] += 1
        if success:
            stats['successful'] += 1
        else:
            stats['failed'] += 1
            if error_type == "payment_declined":
                stats['payment_declined'] += 1
            stats['errors'][error_type] += 1
    
    return success


def run_load_test(alb_url, num_threads, total_requests, test_name=""):
    """
    Run load test with specified number of threads
    Returns: (throughput: float, success_rate: float, duration: float)
    """
    print(f"\n{'='*60}")
    print(f"Load Test: {test_name}")
    print(f"Threads: {num_threads}, Total Requests: {total_requests}")
    print(f"{'='*60}")
    
    # Reset stats
    with stats_lock:
        stats['total_requests'] = 0
        stats['successful'] = 0
        stats['failed'] = 0
        stats['payment_declined'] = 0
        stats['errors'].clear()
        stats['start_time'] = time.time()
    
    # Run load test
    with ThreadPoolExecutor(max_workers=num_threads) as executor:
        futures = [
            executor.submit(worker_thread, alb_url, i)
            for i in range(total_requests)
        ]
        
        # Wait for completion with progress updates
        completed = 0
        last_update = time.time()
        for future in as_completed(futures):
            completed += 1
            if completed % 10000 == 0 or time.time() - last_update > 5:
                elapsed = time.time() - stats['start_time']
                rate = completed / elapsed if elapsed > 0 else 0
                print(f"  Progress: {completed}/{total_requests} ({rate:.0f} req/s)", end='\r')
                last_update = time.time()
    
    stats['end_time'] = time.time()
    duration = stats['end_time'] - stats['start_time']
    
    # Calculate metrics
    with stats_lock:
        successful = stats['successful']
        failed = stats['failed']
        payment_declined = stats['payment_declined']
    
    throughput = successful / duration if duration > 0 else 0
    success_rate = (successful / total_requests * 100) if total_requests > 0 else 0
    
    # Print results
    print(f"\n  Completed: {total_requests} requests")
    print(f"  Duration: {duration:.2f} seconds")
    print(f"  Successful: {successful} ({success_rate:.2f}%)")
    print(f"  Failed: {failed}")
    print(f"  Payment Declined: {payment_declined} (expected ~10%)")
    print(f"  Throughput: {throughput:.2f} successful requests/second")
    
    if stats['errors']:
        print(f"  Error breakdown:")
        for error_type, count in sorted(stats['errors'].items(), key=lambda x: x[1], reverse=True):
            print(f"    {error_type}: {count}")
    
    return throughput, success_rate, duration


def main():
    parser = argparse.ArgumentParser(description='Load test for microservices checkout flow')
    parser.add_argument('--alb-url', default=DEFAULT_ALB_URL,
                       help=f'ALB URL (default: {DEFAULT_ALB_URL})')
    parser.add_argument('--total', type=int, default=DEFAULT_TOTAL_REQUESTS,
                       help=f'Total requests to send (default: {DEFAULT_TOTAL_REQUESTS})')
    parser.add_argument('--threads', type=int, nargs='+', default=DEFAULT_THREAD_COUNTS,
                       help=f'Thread counts to test (default: {DEFAULT_THREAD_COUNTS})')
    parser.add_argument('--single', type=int, metavar='N',
                       help='Run single test with N threads (overrides --threads)')
    parser.add_argument('--warmup', type=int, default=100,
                       help='Warmup requests before main test (default: 100)')
    
    args = parser.parse_args()
    
    print("="*60)
    print("CS6650 Homework 10 - Load Testing")
    print("="*60)
    print(f"ALB URL: {args.alb_url}")
    print(f"Total Requests: {args.total}")
    
    # Warmup
    if args.warmup > 0:
        print(f"\nWarming up with {args.warmup} requests...")
        run_load_test(args.alb_url, 10, args.warmup, "Warmup")
        time.sleep(5)  # Brief pause after warmup
    
    # Determine thread counts to test
    if args.single:
        thread_counts = [args.single]
    else:
        thread_counts = args.threads
    
    # Run tests
    results = []
    for thread_count in thread_counts:
        test_name = f"{thread_count} threads"
        throughput, success_rate, duration = run_load_test(
            args.alb_url, thread_count, args.total, test_name
        )
        results.append({
            'threads': thread_count,
            'throughput': throughput,
            'success_rate': success_rate,
            'duration': duration
        })
        
        # Wait between tests to let queue settle
        if thread_count != thread_counts[-1]:
            print(f"\nWaiting 30 seconds before next test...")
            time.sleep(30)
    
    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    print(f"{'Threads':<10} {'Throughput (req/s)':<20} {'Success Rate':<15} {'Duration (s)':<15}")
    print("-" * 60)
    for r in results:
        print(f"{r['threads']:<10} {r['throughput']:<20.2f} {r['success_rate']:<15.2f} {r['duration']:<15.2f}")
    
    # Find best configuration
    if results:
        best = max(results, key=lambda x: x['throughput'])
        print(f"\nBest Configuration:")
        print(f"  Threads: {best['threads']}")
        print(f"  Throughput: {best['throughput']:.2f} req/s")
        print(f"  Success Rate: {best['success_rate']:.2f}%")
    
    print(f"\n{'='*60}")
    print("Load testing complete!")
    print("Next steps:")
    print("  1. Check RabbitMQ Management UI for queue length")
    print("  2. Adjust warehouse_workers if queue > 1000 messages")
    print("  3. Re-run test with optimal thread count")
    print(f"{'='*60}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nTest interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n\nError: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

