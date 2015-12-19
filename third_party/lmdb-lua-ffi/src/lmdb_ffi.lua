local ffi = require "ffi"

ffi.cdef[[

/* missing types */
typedef uint16_t mode_t;

typedef struct MDB_env MDB_env;
typedef struct MDB_txn MDB_txn;
typedef unsigned int MDB_dbi;
typedef struct MDB_cursor MDB_cursor;
typedef int (MDB_msg_func)(const char *msg, void *ctx);

struct MDB_val {
    size_t mv_size;
    void *mv_data;
};

typedef struct MDB_val MDB_val;

typedef int (MDB_cmp_func)(const MDB_val *a, const MDB_val *b);
typedef void (MDB_rel_func)(MDB_val *item, void *oldptr, void *newptr, void *relctx);

/* mdb_env flags */
static const int MDB_FIXEDMAP = 0x01;
static const int MDB_NOSUBDIR = 0x4000;
static const int MDB_NOSYNC = 0x10000;
static const int MDB_RDONLY = 0x20000;
static const int MDB_NOMETASYNC = 0x40000;
static const int MDB_WRITEMAP = 0x80000;
static const int MDB_MAPASYNC = 0x100000;
static const int MDB_NOTLS = 0x200000;
static const int MDB_NOLOCK = 0x400000;
static const int MDB_NORDAHEAD = 0x800000;
static const int MDB_NOMEMINIT = 0x1000000;

/* mdb_dbi_open flags */
static const int MDB_REVERSEKEY = 0x02;
static const int MDB_DUPSORT = 0x04;
static const int MDB_INTEGERKEY = 0x08;
static const int MDB_DUPFIXED = 0x10;
static const int MDB_INTEGERDUP = 0x20;
static const int MDB_REVERSEDUP = 0x40;
static const int MDB_CREATE = 0x40000;

/* mdb_put flags */
static const int MDB_NOOVERWRITE = 0x10;
static const int MDB_NODUPDATA = 0x20;
static const int MDB_CURRENT = 0x40;
static const int MDB_RESERVE = 0x10000;
static const int MDB_APPEND = 0x20000;
static const int MDB_APPENDDUP = 0x40000;
static const int MDB_MULTIPLE = 0x80000;


typedef enum MDB_cursor_op {
    MDB_FIRST,
    MDB_FIRST_DUP,
    MDB_GET_BOTH,
    MDB_GET_BOTH_RANGE,
    MDB_GET_CURRENT,
    MDB_GET_MULTIPLE,
    MDB_LAST,
    MDB_LAST_DUP,
    MDB_NEXT,
    MDB_NEXT_DUP,
    MDB_NEXT_MULTIPLE,
    MDB_NEXT_NODUP,
    MDB_PREV,
    MDB_PREV_DUP,
    MDB_PREV_NODUP,
    MDB_SET,
    MDB_SET_KEY,
    MDB_SET_RANGE
} MDB_cursor_op;

static const int MDB_SUCCESS =  0;
static const int MDB_KEYEXIST = (-30799);
static const int MDB_NOTFOUND = (-30798);
static const int MDB_PAGE_NOTFOUND = (-30797);
static const int MDB_CORRUPTED = (-30796);
static const int MDB_PANIC = (-30795);
static const int MDB_VERSION_MISMATCH = (-30794);
static const int MDB_INVALID = (-30793);
static const int MDB_MAP_FULL = (-30792);
static const int MDB_DBS_FULL = (-30791);
static const int MDB_READERS_FULL = (-30790);
static const int MDB_TLS_FULL = (-30789);
static const int MDB_TXN_FULL = (-30788);
static const int MDB_CURSOR_FULL = (-30787);
static const int MDB_PAGE_FULL = (-30786);
static const int MDB_MAP_RESIZED = (-30785);
static const int MDB_INCOMPATIBLE = (-30784);
static const int MDB_BAD_RSLOT = (-30783);
static const int MDB_BAD_TXN = (-30782);
static const int MDB_BAD_VALSIZE = (-30781);
static const int MDB_LAST_ERRCODE = MDB_BAD_VALSIZE;

struct MDB_stat {
    unsigned int ms_psize;
    unsigned int ms_depth;
    size_t ms_branch_pages;
    size_t ms_leaf_pages;
    size_t ms_overflow_pages;
    size_t ms_entries;
};
typedef struct MDB_stat MDB_stat;

struct MDB_envinfo {
    void    *me_mapaddr;
    size_t  me_mapsize;
    size_t  me_last_pgno;
    size_t  me_last_txnid;
    unsigned int me_maxreaders;
    unsigned int me_numreaders;
};
typedef struct MDB_envinfo MDB_envinfo;

char *mdb_version(int *major, int *minor, int *patch);
char *mdb_strerror(int err);
int  mdb_env_create(MDB_env **env);
int  mdb_env_open(MDB_env *env, const char *path, unsigned int flags, mode_t mode);
int  mdb_env_copy(MDB_env *env, const char *path);
int  mdb_env_stat(MDB_env *env, MDB_stat *stat);
int  mdb_env_info(MDB_env *env, MDB_envinfo *stat);
int  mdb_env_sync(MDB_env *env, int force);
void mdb_env_close(MDB_env *env);
int  mdb_env_set_flags(MDB_env *env, unsigned int flags, int onoff);
int  mdb_env_get_flags(MDB_env *env, unsigned int *flags);
int  mdb_env_get_path(MDB_env *env, const char **path);
int  mdb_env_set_mapsize(MDB_env *env, size_t size);
int  mdb_env_set_maxreaders(MDB_env *env, unsigned int readers);
int  mdb_env_get_maxreaders(MDB_env *env, unsigned int *readers);
int  mdb_env_set_maxdbs(MDB_env *env, MDB_dbi dbs);

int  mdb_txn_begin(MDB_env *env, MDB_txn *parent, unsigned int flags, MDB_txn **txn);
int  mdb_txn_commit(MDB_txn *txn);
void mdb_txn_abort(MDB_txn *txn);
void mdb_txn_reset(MDB_txn *txn);
int  mdb_txn_renew(MDB_txn *txn);

int  mdb_dbi_open(MDB_txn *txn, const char *name, unsigned int flags, MDB_dbi *dbi);
int  mdb_stat(MDB_txn *txn, MDB_dbi dbi, MDB_stat *stat);
void mdb_dbi_close(MDB_env *env, MDB_dbi dbi);
int  mdb_drop(MDB_txn *txn, MDB_dbi dbi, int del);
int  mdb_set_compare(MDB_txn *txn, MDB_dbi dbi, MDB_cmp_func *cmp);
int  mdb_set_dupsort(MDB_txn *txn, MDB_dbi dbi, MDB_cmp_func *cmp);
int  mdb_set_relfunc(MDB_txn *txn, MDB_dbi dbi, MDB_rel_func *rel);
int  mdb_set_relctx(MDB_txn *txn, MDB_dbi dbi, void *ctx);
int  mdb_get(MDB_txn *txn, MDB_dbi dbi, MDB_val *key, MDB_val *data);
int  mdb_put(MDB_txn *txn, MDB_dbi dbi, MDB_val *key, MDB_val *data,
             unsigned int flags);
int  mdb_del(MDB_txn *txn, MDB_dbi dbi, MDB_val *key, MDB_val *data);

int  mdb_cursor_open(MDB_txn *txn, MDB_dbi dbi, MDB_cursor **cursor);
void mdb_cursor_close(MDB_cursor *cursor);
int  mdb_cursor_renew(MDB_txn *txn, MDB_cursor *cursor);

MDB_txn *mdb_cursor_txn(MDB_cursor *cursor);
MDB_dbi mdb_cursor_dbi(MDB_cursor *cursor);

int  mdb_cursor_get(MDB_cursor *cursor, MDB_val *key, MDB_val *data,
                    MDB_cursor_op op);
int  mdb_cursor_put(MDB_cursor *cursor, MDB_val *key, MDB_val *data,
                    unsigned int flags);
int  mdb_cursor_del(MDB_cursor *cursor, unsigned int flags);
int  mdb_cursor_count(MDB_cursor *cursor, size_t *countp);
int  mdb_cmp(MDB_txn *txn, MDB_dbi dbi, const MDB_val *a, const MDB_val *b);
int  mdb_dcmp(MDB_txn *txn, MDB_dbi dbi, const MDB_val *a, const MDB_val *b);

int mdb_reader_check(MDB_env *env, int *dead);
int mdb_reader_list(MDB_env *env, MDB_msg_func *func, void *ctx);
]]

local lmdb = ffi.load("lmdb")

return lmdb
