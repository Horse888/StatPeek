// Read-only, per-process macOS CPU/wakeup counters. Energy scores are not watts.
#include <libproc.h>
#include <mach/mach_time.h>
#include <sys/resource.h>
#include <time.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
int main(int argc,char **argv) {
 if(argc!=3) { fprintf(stderr,"usage: %s PID SECONDS\n",argv[0]);return 2; }
 pid_t pid=atoi(argv[1]);int seconds=atoi(argv[2]);if(pid<=0||seconds<1||seconds>300)return 2;
 struct rusage_info_v4 first,previous,current;
 if(proc_pid_rusage(pid,RUSAGE_INFO_V4,(rusage_info_t*)&first)!=0){perror("proc_pid_rusage");return 1;}
 mach_timebase_info_data_t tb;mach_timebase_info(&tb);double ticks_to_ns=(double)tb.numer/tb.denom;
 previous=first;double start=now(),prior=start;
 printf("{\"pid\":%d,\"ticks_to_ns\":%.9f,\"samples\":[",pid,ticks_to_ns);fflush(stdout);
 for(int i=0;i<seconds;i++) {
  sleep(1);if(proc_pid_rusage(pid,RUSAGE_INFO_V4,(rusage_info_t*)&current)!=0){perror("proc_pid_rusage");return 1;}
  double t=now(),dt=t-prior;
  printf("%s{\"elapsed_s\":%.6f,\"cpu_percent\":%.6f,\"interrupt_wakeups_per_s\":%.6f,\"package_idle_wakeups_per_s\":%.6f}",i?",":"",t-start,((current.ri_user_time-previous.ri_user_time)+(current.ri_system_time-previous.ri_system_time))*ticks_to_ns/1e9/dt*100,(current.ri_interrupt_wkups-previous.ri_interrupt_wkups)/dt,(current.ri_pkg_idle_wkups-previous.ri_pkg_idle_wkups)/dt);fflush(stdout);
  previous=current;prior=t;
 }
 double dt=prior-start;
 printf("],\"duration_s\":%.6f,\"cpu_percent\":%.6f,\"interrupt_wakeups_per_s\":%.6f,\"package_idle_wakeups_per_s\":%.6f,\"physical_footprint_bytes\":%llu}\n",dt,((current.ri_user_time-first.ri_user_time)+(current.ri_system_time-first.ri_system_time))*ticks_to_ns/1e9/dt*100,(current.ri_interrupt_wkups-first.ri_interrupt_wkups)/dt,(current.ri_pkg_idle_wkups-first.ri_pkg_idle_wkups)/dt,current.ri_phys_footprint);
 return 0;
}
