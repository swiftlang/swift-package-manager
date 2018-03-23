#include <pthread.h>
#include <assert.h>

static void *increment(void *intp) {
    int *i = intp;
    *i = *i + 1;
    return 0;
}

static pthread_t t;

void incrementInThread(int *ptr) {
    int r = pthread_create(&t, 0, increment, ptr);
    assert(r == 0);
}

void joinThread() {
    pthread_join(t, 0);
}
