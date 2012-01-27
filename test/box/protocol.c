
#include <stdlib.h>
#include <stdio.h>
#include <inttypes.h>

#include "util.h"
#include "errcode.h"

#include <libtnt/tnt.h>
#include <libtnt/tnt_net.h>
#include <libtnt/tnt_io.h>

/** Client handler. Reused between tests. */
struct tnt_stream *t;

/** Test the ping command. */
void test_ping()
{
	const char message[]= {
		0xd, 0x0, 0x0, 0x0,    0x11, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0,    0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0,    0x1, 0x0, 0x0, 0x0,
		0x4, 0x1, 0x0, 0x0, 0x0 };

	tnt_io_send_raw(TNT_SNET_CAST(t), (char*)message, sizeof(message), 1);
	t->wrcnt++;

	struct tnt_iter i;
	tnt_iter_stream(&i, t);
	tnt_next(&i);
	struct tnt_reply *r = TNT_ISTREAM_REPLY(&i);
	printf("return_code: %"PRIu32"\n", r->code); /* =0 */
	tnt_iter_free(&i);
}

/** A test case for Bug#702397
 * https://bugs.launchpad.net/tarantool/+bug/702397 "If SELECT
 * request specifies tuple count 0, no error"
 */

void test_bug702397()
{
	const char message[]= {
		0x11, 0x0, 0x0, 0x0,    0x14, 0x0, 0x0, 0x0,    0x0, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0,     0x0, 0x0, 0x0, 0x0,     0x0, 0x0, 0x0, 0x0,
		0xff, 0xff, 0xff, 0xff, 0x0, 0x0, 0x0, 0x0 };

	tnt_io_send_raw(TNT_SNET_CAST(t), (char*)message, sizeof(message), 1);
	t->wrcnt++;

	struct tnt_iter i;
	tnt_iter_stream(&i, t);
	tnt_next(&i);
	struct tnt_reply *r = TNT_ISTREAM_REPLY(&i);
	printf("return_code: %s, %s\n",
	       tnt_errcode_str(r->code >> 8), r->error);
	tnt_iter_free(&i);
}

/** A test case for Bug#702399
 * https://bugs.launchpad.net/tarantool/+bug/702399
 * ERR_CODE_ILLEGAL_PARAMS is returned when there is no such key
 */

void test_bug702399()
{
	const char message[]= {
		0x11, 0x0, 0x0, 0x0,    0x1d, 0x0, 0x0, 0x0,
		0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
		0x1, 0x0, 0x0, 0x0,     0x0, 0x0, 0x0, 0x0,
		0xff, 0xff, 0xff, 0xff,
		0x1, 0x0, 0x0, 0x0,     0x1, 0x0, 0x0, 0x0,
		0x4,    0x1, 0x0, 0x0, 0x0 };

	tnt_io_send_raw(TNT_SNET_CAST(t), (char*)message, sizeof(message), 1);
	t->wrcnt++;

	struct tnt_iter i;
	tnt_iter_stream(&i, t);
	tnt_next(&i);
	struct tnt_reply *r = TNT_ISTREAM_REPLY(&i);
	printf("return_code: %s, %s\n",
	       tnt_errcode_str(r->code >> 8), r->error);
	tnt_iter_free(&i);
}

int main()
{
	t = tnt_net(NULL);
	if (t == NULL)
		return 1;
	tnt_set(t, TNT_OPT_HOSTNAME, "localhost");
	tnt_set(t, TNT_OPT_PORT, 33013);
	if (tnt_init(t) == -1)
		return 1;
	if (tnt_connect(t) == -1)
		return 1;

	test_ping();
	test_bug702397();
	test_bug702399();

	tnt_stream_free(t);
	return 0;
}
