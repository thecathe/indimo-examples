package main

import (
	"fmt"
	"os"
	"strconv"
)

type P = int

/*
The main thread will halt unless (n + m) >= k.
Returns a k-length slice of P's, where:
n is the bound for the return-channel;
m limits the number of goroutines to spawn, halting the main thread while the limit is exceeded; and
k is the number of goroutines that are spawned that will send their own P on the return-channel.
Each time a goroutine is spawned, a token is added to the limit-channel which is only removed once it has sent it's P on return-channel.
Therefore, if the number of goroutines spawned k is greater than the bounds of the return-channel n and the limit m allows for, then the main thread will get stuck waiting to add a token to limit, which is a deadlock since the goroutines will get stuck waiting for P's to be received by the main thread.
*/
func FindAll(n int, m int, k int) []P {
	found := make(chan P, n)
	limit := make(chan struct{}, m)
	for i := 0; i < k; i++ {
		limit <- struct{}{} // push token
		go func() {         // spawn thread
			/* (...find P...) */
			p := i
			found <- p // send P
			<-limit    // pop token
		}()
	}
	var results []P
	for j := 0; j < k; j++ {
		p := <-found // receive P
		results = append(results, p)
	}
	return results
}

func run(x chan []P, n int, m int, k int) {
	x <- FindAll(n, m, k)
}

func get_int(x string) int {
	i, err := strconv.Atoi(x)
	if err != nil {
		panic(err)
	}
	return i
}

func get_args() (int, int, int) {
	errmsg := "Unrecognised input.\nEither use one of the presets \"safe\" or \"unsafe\", or input 3 integers for n, m, k.\nA \"safe\" input is one where: n + m >= k"
	if len(os.Args) == 2 {
		switch s := os.Args[1]; s {
		case "safe":
			return 5, 6, 3
		case "unsafe":
			return 1, 10, 12
		default:
			panic(errmsg)
		}
	} else if len(os.Args) != 4 {
		panic(errmsg)
	} else {
		return get_int(os.Args[1]), get_int(os.Args[2]), get_int(os.Args[3])
	}
}

func main() {
	n, m, k := get_args()
	fmt.Printf("spawning FindAll with:\nn := %v\nm := %v\nk := %v\n", n, m, k)
	x := make(chan []P, 1)
	go run(x, n, m, k)
	y := <-x
	fmt.Printf("received: %v", y)
}
