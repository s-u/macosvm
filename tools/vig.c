#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/vsock.h>

#define MSG_ERROR 0x1000
#define MSG_UNSUPPORTED (MSG_ERROR | 1)

typedef struct msg_header {
    uint32_t msg;
    uint32_t mid;
    uint64_t len;    
} msg_header_t;

int main(int ac, char **av) {
    struct sockaddr_vm sa;
    msg_header_t msg = { 0, 0, 0 };
    int port = 1010;
    memset(&sa, 0, sizeof(sa));
    sa.svm_len = sizeof(sa);
    sa.svm_family = AF_VSOCK;
    sa.svm_port =  port;
    sa.svm_cid  =  VMADDR_CID_HOST;
    int s = socket(AF_VSOCK, SOCK_STREAM, 0);
    if (s == -1) {
	perror("ERROR: cannot create socket");
	return 0;
    }
    if (connect(s, (const struct sockaddr *) &sa, sizeof(sa)) == -1) {
	perror("ERROR: cannot connect");
	return 0;
    }
    printf("Connected to port %d\n", port);

    while (1) {
	printf("Send = %d\n", send(s, &msg, sizeof(msg), 0));
	int n = recv(s, &msg, sizeof(msg), 0);
	printf("recv = %d\n", n);
	if (n == sizeof(msg))
	    printf(" ok, msg = %x, len = %lu\n", msg.msg,
		   (unsigned long) msg.len);

	char q[10];
	if (!fgets(q, sizeof(q), stdin) ||
	    *q == 'q') break;
    }
    close(s);
    return 0;
}
