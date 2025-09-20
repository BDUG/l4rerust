#include <signal.h>
#include <stdio.h>
#include <unistd.h>

int main(void)
{
  printf("[custom-init] Minimal init starting (PID %d)\n", getpid());
  fflush(stdout);

  struct sigaction ignore = {0};
  ignore.sa_handler = SIG_IGN;
  sigaction(SIGINT, &ignore, NULL);
  sigaction(SIGTERM, &ignore, NULL);

  while (1) {
    puts("[custom-init] System idle; sleeping for 5 seconds.");
    fflush(stdout);
    sleep(5);
  }

  return 0;
}
