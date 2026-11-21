/*
 * HolyC Unix Kernel - RedSea Filesystem Driver & Inspector (RedSea.HC)
 * Parses Terry Davis's 64-bit flat contiguous cluster RedSea filesystem format.
 * Enables mounting, inspecting, and extracting files from TempleOS ISO/raw disk images.
 *
 * "RedSea is a simple 64-bit file system. An idiot admires complexity." - Terry A. Davis
 */

#ifndef REDSEA_HC
#define REDSEA_HC

#include "Types.HC"
#include "VFS.HC"
#include "Syscall.HC"

#define REDSEA_SECTOR_SIZE    512
#define REDSEA_SIGNATURE      0x88AA
#define REDSEA_ATTR_DIR       0x10
#define REDSEA_ATTR_READONLY  0x01
#define REDSEA_MAX_ENTRIES    8
#define REDSEA_MAX_CLUSTERS   256

class CRedSeaBoot {
    U8  jmp[3];
    U8  oem_name[8];
    U16 bytes_per_sector;
    U8  sectors_per_cluster;
    U16 reserved_sectors;
    U32 total_sectors;
    U64 root_cluster;
    U16 signature;
};

class CRedSeaDirEntry {
    U16 attr;
    char name[38];
    I64 clus;
    I64 size;
    I64 datetime;
};

static Bool RedSeaBitmapGet(const U8 *bitmap, I64 clus) {
    if (!bitmap || clus < 0 || clus >= REDSEA_SECTOR_SIZE * 8) return FALSE;
    return ((bitmap[clus / 8] >> (clus % 8)) & 1) != 0;
}

static U0 RedSeaBitmapSet(U8 *bitmap, I64 clus, Bool used) {
    if (!bitmap || clus < 0 || clus >= REDSEA_SECTOR_SIZE * 8) return;
    if (used) bitmap[clus / 8] |= (U8)(1 << (clus % 8));
    else bitmap[clus / 8] &= (U8)~(1 << (clus % 8));
}

/* Inspect a RedSea image header and dump filesystem volume information */
I64 RedSeaInspect(const char *image_path, char *out_buf, I64 max_len) {
    if (!image_path || !out_buf || max_len <= 0) return -1;

    I64 fd = SysOpen((const U8*)image_path, O_RDONLY);
    if (fd < 0) {
        snprintf(out_buf, max_len, "redsea: cannot open image '%s'\n", image_path);
        return -1;
    }

    U8 sector[REDSEA_SECTOR_SIZE];
    I64 n = SysRead(fd, sector, sizeof(sector));
    SysClose(fd);

    if (n < REDSEA_SECTOR_SIZE) {
        snprintf(out_buf, max_len, "redsea: image too small to be valid RedSea volume\n");
        return -1;
    }

    /* Check RedSea boot signature at byte offset 510 or header */
    U16 sig = (U16)(sector[510] | (sector[511] << 8));
    Bool is_redsea = (sig == REDSEA_SIGNATURE || memcmp(sector + 3, "TEMPLEOS", 8) == 0 || memcmp(sector + 3, "REDSEA", 6) == 0);
    if (!is_redsea) {
        snprintf(out_buf, max_len, "redsea: invalid boot signature 0x%04X in '%s'\n", (unsigned int)sig, image_path);
        return -1;
    }

    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "\n\033[93m====================================================\033[0m\n"
        "\033[96mRedSea Filesystem Volume Inspector (TempleOS 64-Bit)\033[0m\n"
        "\033[93m====================================================\033[0m\n"
        "  Target Image     : %s\n"
        "  OEM / Filesystem : %-8.8s\n"
        "  Sector Size      : %u bytes\n"
        "  Cluster Size     : 512 bytes (1 sector / cluster)\n"
        "  Boot Signature   : 0x%04X (%s)\n"
        "  Root Dir Cluster : 2\n"
        "  Addressing       : 64-bit Flat Contiguous Clusters\n"
        "  Status           : \033[92mVALID REDSEA VOLUME\033[0m\n\n",
        image_path,
        (char*)sector + 3,
        REDSEA_SECTOR_SIZE,
        (unsigned int)sig,
        is_redsea ? "VALID" : "COMPATIBLE");

    return offset;
}

I64 RedSeaInspectJson(const char *image_path, char *out_buf, I64 max_len) {
    if (!image_path || !out_buf || max_len <= 0) return -1;

    CKernelStat st;
    if (SysStat((const U8*)image_path, &st) != 0) {
        snprintf(out_buf, max_len, "{\"valid\":false,\"error\":\"cannot stat image\"}\n");
        return -1;
    }

    I64 fd = SysOpen((const U8*)image_path, O_RDONLY);
    if (fd < 0) {
        snprintf(out_buf, max_len, "{\"valid\":false,\"error\":\"cannot open image\"}\n");
        return -1;
    }

    U8 sector[REDSEA_SECTOR_SIZE];
    I64 n = SysRead(fd, sector, sizeof(sector));
    SysClose(fd);

    if (n < REDSEA_SECTOR_SIZE) {
        snprintf(out_buf, max_len, "{\"valid\":false,\"error\":\"image too small\"}\n");
        return -1;
    }

    U16 sig = (U16)(sector[510] | (sector[511] << 8));
    Bool is_redsea = (sig == REDSEA_SIGNATURE && (memcmp(sector + 3, "TEMPLEOS", 8) == 0 || memcmp(sector + 3, "REDSEA", 6) == 0));
    char oem[9];
    memcpy(oem, sector + 3, 8);
    oem[8] = '\0';
    for (int i = 7; i >= 0 && oem[i] == ' '; --i) oem[i] = '\0';

    I64 total_clusters = st.st_size / REDSEA_SECTOR_SIZE;
    snprintf(out_buf, max_len,
        "{\"valid\":%s,\"image\":\"%s\",\"oem\":\"%s\",\"sector_size\":%d,\"cluster_size\":%d,"
        "\"signature\":\"0x%04X\",\"root_cluster\":2,\"total_clusters\":%lld,\"size_bytes\":%lld}\n",
        is_redsea ? "true" : "false",
        image_path,
        oem,
        REDSEA_SECTOR_SIZE,
        REDSEA_SECTOR_SIZE,
        (unsigned int)sig,
        (long long)total_clusters,
        (long long)st.st_size);
    return is_redsea ? 0 : -1;
}

/* List files inside a RedSea filesystem image */
I64 RedSeaList(const char *image_path, char *out_buf, I64 max_len) {
    if (!image_path || !out_buf || max_len <= 0) return -1;

    I64 fd = SysOpen((const U8*)image_path, O_RDONLY);
    if (fd < 0) {
        snprintf(out_buf, max_len, "redsea: cannot open image '%s'\n", image_path);
        return -1;
    }

    /* Seek to Root Directory at Sector 2 */
    SysSeek(fd, 2 * REDSEA_SECTOR_SIZE, VFS_SEEK_SET);
    U8 dir_sector[REDSEA_SECTOR_SIZE];
    I64 n = SysRead(fd, dir_sector, sizeof(dir_sector));
    SysClose(fd);

    if (n < REDSEA_SECTOR_SIZE) {
        snprintf(out_buf, max_len, "redsea: cannot read root directory sector\n");
        return -1;
    }

    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset,
        "\033[93mPERMS      CLUSTER       SIZE  FILENAME\033[0m\n"
        "-----------------------------------------------\n");

    /* Parse 64-byte directory entries */
    I64 entry_count = REDSEA_SECTOR_SIZE / 64;
    for (I64 i = 0; i < entry_count; ++i) {
        CRedSeaDirEntry *entry = (CRedSeaDirEntry*)(dir_sector + (i * 64));
        if (entry->name[0] == '\0') continue;

        char safe_name[39];
        memcpy(safe_name, entry->name, 38);
        safe_name[38] = '\0';

        const char *type_str = (entry->attr & REDSEA_ATTR_DIR) ? "drwxr-xr-x" : "-rw-r--r--";
        const char *color_str = (entry->attr & REDSEA_ATTR_DIR) ? "\033[96m" : "\033[92m";

        offset += snprintf(out_buf + offset, max_len - offset,
            "%-10s %7lld %10lld  %s%s\033[0m\n",
            type_str,
            (long long)entry->clus,
            (long long)entry->size,
            color_str,
            safe_name);

        if (offset >= max_len - 128) break;
    }

    return offset;
}

I64 RedSeaListJson(const char *image_path, char *out_buf, I64 max_len) {
    if (!image_path || !out_buf || max_len <= 0) return -1;

    I64 fd = SysOpen((const U8*)image_path, O_RDONLY);
    if (fd < 0) {
        snprintf(out_buf, max_len, "{\"error\":\"cannot open image\"}\n");
        return -1;
    }

    SysSeek(fd, 2 * REDSEA_SECTOR_SIZE, VFS_SEEK_SET);
    U8 dir_sector[REDSEA_SECTOR_SIZE];
    I64 n = SysRead(fd, dir_sector, sizeof(dir_sector));
    SysClose(fd);

    if (n < REDSEA_SECTOR_SIZE) {
        snprintf(out_buf, max_len, "{\"error\":\"cannot read root directory\"}\n");
        return -1;
    }

    I64 offset = 0;
    offset += snprintf(out_buf + offset, max_len - offset, "{\"image\":\"%s\",\"entries\":[", image_path);
    Bool first = TRUE;
    I64 entry_count = REDSEA_SECTOR_SIZE / 64;
    for (I64 i = 0; i < entry_count; ++i) {
        CRedSeaDirEntry *entry = (CRedSeaDirEntry*)(dir_sector + (i * 64));
        if (entry->name[0] == '\0') continue;

        char safe_name[39];
        memcpy(safe_name, entry->name, 38);
        safe_name[38] = '\0';
        I64 clusters = (entry->size > 0) ? ((entry->size + REDSEA_SECTOR_SIZE - 1) / REDSEA_SECTOR_SIZE) : 1;

        offset += snprintf(out_buf + offset, max_len - offset,
            "%s{\"name\":\"%s\",\"cluster\":%lld,\"clusters\":%lld,\"size\":%lld,\"is_dir\":%s}",
            first ? "" : ",",
            safe_name,
            (long long)entry->clus,
            (long long)clusters,
            (long long)entry->size,
            (entry->attr & REDSEA_ATTR_DIR) ? "true" : "false");
        first = FALSE;
        if (offset >= max_len - 128) break;
    }
    offset += snprintf(out_buf + offset, max_len - offset, "]}\n");
    return offset;
}

/* Read a file's actual contiguous clusters from a RedSea image */
I64 RedSeaCat(const char *image_path, const char *filename, char *out_buf, I64 max_len) {
    if (!image_path || !filename || !*filename || !out_buf || max_len <= 0) return -K_EINVAL;
    out_buf[0] = '\0';

    CKernelStat st;
    if (SysStat((const U8*)image_path, &st) != 0) return -K_ENOENT;
    if (st.st_size < 3 * REDSEA_SECTOR_SIZE) return -K_EINVAL;

    I64 fd = SysOpen((const U8*)image_path, O_RDONLY);
    if (fd < 0) return -K_ENOENT;

    /* Validate boot sector signature */
    U8 boot_sec[REDSEA_SECTOR_SIZE];
    if (SysRead(fd, boot_sec, REDSEA_SECTOR_SIZE) < REDSEA_SECTOR_SIZE) {
        SysClose(fd);
        return -K_EINVAL;
    }
    U16 sig = (U16)(boot_sec[510] | (boot_sec[511] << 8));
    if (sig != REDSEA_SIGNATURE) {
        SysClose(fd);
        return -K_EINVAL;
    }

    /* Read Root Directory at Sector 2 */
    SysSeek(fd, 2 * REDSEA_SECTOR_SIZE, VFS_SEEK_SET);
    U8 dir_sector[REDSEA_SECTOR_SIZE];
    if (SysRead(fd, dir_sector, REDSEA_SECTOR_SIZE) < REDSEA_SECTOR_SIZE) {
        SysClose(fd);
        return -K_EINVAL;
    }

    I64 entry_count = REDSEA_SECTOR_SIZE / 64;
    CRedSeaDirEntry *found = NULL;
    for (I64 i = 0; i < entry_count; ++i) {
        CRedSeaDirEntry *entry = (CRedSeaDirEntry*)(dir_sector + (i * 64));
        if (entry->name[0] == '\0') continue;
        char safe_name[39];
        memcpy(safe_name, entry->name, 38);
        safe_name[38] = '\0';
        if (strcasecmp(safe_name, filename) == 0) {
            found = entry;
            break;
        }
    }

    if (!found) {
        SysClose(fd);
        return -K_ENOENT;
    }

    /* Validate contiguous cluster range against image size */
    if (found->clus < 3 || found->size < 0) {
        SysClose(fd);
        return -K_EINVAL;
    }
    I64 byte_offset = found->clus * REDSEA_SECTOR_SIZE;
    if (byte_offset >= st.st_size || byte_offset + found->size > st.st_size) {
        SysClose(fd);
        return -K_EINVAL;
    }

    SysSeek(fd, byte_offset, VFS_SEEK_SET);
    I64 to_read = Min(found->size, max_len - 1);
    I64 n = (to_read > 0) ? SysRead(fd, (U8*)out_buf, to_read) : 0;
    SysClose(fd);

    if (n < 0) n = 0;
    /* Strip trailing zero padding if file size in directory entry included padding */
    I64 actual_len = n;
    while (actual_len > 0 && out_buf[actual_len - 1] == '\0') {
        actual_len--;
    }
    out_buf[actual_len] = '\0';
    return actual_len;
}

/* Write or update a file inside a RedSea image using contiguous cluster allocation */
I64 RedSeaPut(const char *image_path, const char *filename, const U8 *data, I64 size) {
    if (!image_path || !filename || !*filename || size < 0) return -K_EINVAL;
    if (strlen(filename) > 37 || strchr(filename, '/') != NULL || strstr(filename, "..") != NULL) {
        return -K_EINVAL;
    }
    if (size > 64 * REDSEA_SECTOR_SIZE) return -K_EINVAL;

    CKernelStat st;
    if (SysStat((const U8*)image_path, &st) != 0 || st.st_size < 3 * REDSEA_SECTOR_SIZE) {
        return -K_EINVAL;
    }

    I64 fd = SysOpen((const U8*)image_path, O_RDWR);
    if (fd < 0) return fd;

    U8 boot_sec[REDSEA_SECTOR_SIZE];
    U8 bitmap_sec[REDSEA_SECTOR_SIZE];
    U8 dir_sec[REDSEA_SECTOR_SIZE];

    if (SysRead(fd, boot_sec, REDSEA_SECTOR_SIZE) < REDSEA_SECTOR_SIZE ||
        SysRead(fd, bitmap_sec, REDSEA_SECTOR_SIZE) < REDSEA_SECTOR_SIZE ||
        SysRead(fd, dir_sec, REDSEA_SECTOR_SIZE) < REDSEA_SECTOR_SIZE) {
        SysClose(fd);
        return -K_EIO;
    }

    U16 sig = (U16)(boot_sec[510] | (boot_sec[511] << 8));
    if (sig != REDSEA_SIGNATURE) {
        SysClose(fd);
        return -K_EINVAL;
    }

    I64 needed_clusters = (size > 0) ? ((size + REDSEA_SECTOR_SIZE - 1) / REDSEA_SECTOR_SIZE) : 1;
    I64 entry_count = REDSEA_SECTOR_SIZE / 64;
    CRedSeaDirEntry *target_entry = NULL;
    CRedSeaDirEntry *free_entry = NULL;

    for (I64 i = 0; i < entry_count; ++i) {
        CRedSeaDirEntry *entry = (CRedSeaDirEntry*)(dir_sec + (i * 64));
        if (entry->name[0] == '\0') {
            if (!free_entry) free_entry = entry;
            continue;
        }
        char safe_name[39];
        memcpy(safe_name, entry->name, 38);
        safe_name[38] = '\0';
        if (strcasecmp(safe_name, filename) == 0) {
            target_entry = entry;
            break;
        }
    }

    if (!target_entry && !free_entry) {
        SysClose(fd);
        return -K_ENFILE; /* Root directory full */
    }

    /* If overwriting existing entry, free its old bitmap bits first */
    if (target_entry && target_entry->clus >= 3) {
        I64 old_clusters = (target_entry->size > 0) ? ((target_entry->size + REDSEA_SECTOR_SIZE - 1) / REDSEA_SECTOR_SIZE) : 1;
        for (I64 c = 0; c < old_clusters; ++c) {
            RedSeaBitmapSet(bitmap_sec, target_entry->clus + c, FALSE);
        }
    }

    /* Find contiguous free clusters starting at cluster 3 */
    I64 start_clus = -1;
    for (I64 cand = 3; cand + needed_clusters <= REDSEA_MAX_CLUSTERS; ++cand) {
        Bool ok = TRUE;
        for (I64 k = 0; k < needed_clusters; ++k) {
            if (RedSeaBitmapGet(bitmap_sec, cand + k)) {
                ok = FALSE;
                break;
            }
        }
        if (ok) {
            start_clus = cand;
            break;
        }
    }

    if (start_clus < 3) {
        SysClose(fd);
        return -K_ENFILE;
    }

    /* Mark contiguous clusters allocated in Sector 1 bitmap */
    for (I64 k = 0; k < needed_clusters; ++k) {
        RedSeaBitmapSet(bitmap_sec, start_clus + k, TRUE);
    }

    CRedSeaDirEntry *ent = target_entry ? target_entry : free_entry;
    MemSet(ent, 0, sizeof(CRedSeaDirEntry));
    ent->attr = 0;
    strncpy(ent->name, filename, 37);
    ent->name[37] = '\0';
    ent->clus = start_clus;
    ent->size = size;
    ent->datetime = GetTimestampMs() / 1000;

    /* Write updated bitmap (Sector 1) and root directory (Sector 2) */
    SysSeek(fd, 1 * REDSEA_SECTOR_SIZE, VFS_SEEK_SET);
    SysWrite(fd, bitmap_sec, REDSEA_SECTOR_SIZE);
    SysWrite(fd, dir_sec, REDSEA_SECTOR_SIZE);

    /* Write contiguous data clusters */
    SysSeek(fd, start_clus * REDSEA_SECTOR_SIZE, VFS_SEEK_SET);
    U8 sector_buf[REDSEA_SECTOR_SIZE];
    I64 remaining = size;
    I64 data_off = 0;
    for (I64 k = 0; k < needed_clusters; ++k) {
        MemSet(sector_buf, 0, REDSEA_SECTOR_SIZE);
        I64 chunk = (remaining > REDSEA_SECTOR_SIZE) ? REDSEA_SECTOR_SIZE : remaining;
        if (chunk > 0 && data) {
            MemCpy(sector_buf, data + data_off, chunk);
            data_off += chunk;
            remaining -= chunk;
        }
        SysWrite(fd, sector_buf, REDSEA_SECTOR_SIZE);
    }

    SysClose(fd);
    return start_clus;
}

/* Extract a file from a RedSea image into the VFS */
I64 RedSeaExtract(const char *image_path, const char *filename, const char *dest_vfs_path) {
    if (!image_path || !filename || !dest_vfs_path || !*dest_vfs_path) return -K_EINVAL;
    char *buf = (char*)MAlloc(64 * REDSEA_SECTOR_SIZE + 1);
    I64 len = RedSeaCat(image_path, filename, buf, 64 * REDSEA_SECTOR_SIZE + 1);
    if (len < 0) {
        Free(buf);
        return len;
    }
    CTask *t = TaskGetCurrent();
    const U8 *cwd = t ? t->cwd : (const U8*)"/";
    I64 inum = VFSCreateFile((const U8*)dest_vfs_path, cwd, (const U8*)buf, len);
    Free(buf);
    return (inum >= 0) ? 0 : -K_EIO;
}

/* Perform full RedSea volume consistency verification (fsck) */
I64 RedSeaFsck(const char *image_path, Bool json_mode, char *out_buf, I64 max_len) {
    if (!image_path || !out_buf || max_len <= 0) return -1;

    CKernelStat st;
    if (SysStat((const U8*)image_path, &st) != 0) {
        if (json_mode) snprintf(out_buf, max_len, "{\"valid\":false,\"error\":\"cannot stat image\"}\n");
        else snprintf(out_buf, max_len, "redsea fsck: cannot stat '%s'\n", image_path);
        return -1;
    }

    if (st.st_size < 3 * REDSEA_SECTOR_SIZE || (st.st_size % REDSEA_SECTOR_SIZE) != 0) {
        if (json_mode) snprintf(out_buf, max_len, "{\"valid\":false,\"error\":\"truncated or unaligned volume size\",\"size\":%lld}\n", (long long)st.st_size);
        else snprintf(out_buf, max_len, "redsea fsck: FAILED (truncated or unaligned volume size %lld bytes)\n", (long long)st.st_size);
        return -1;
    }

    I64 fd = SysOpen((const U8*)image_path, O_RDONLY);
    if (fd < 0) {
        if (json_mode) snprintf(out_buf, max_len, "{\"valid\":false,\"error\":\"cannot open image\"}\n");
        else snprintf(out_buf, max_len, "redsea fsck: cannot open '%s'\n", image_path);
        return -1;
    }

    U8 boot_sec[REDSEA_SECTOR_SIZE];
    U8 bitmap_sec[REDSEA_SECTOR_SIZE];
    U8 dir_sec[REDSEA_SECTOR_SIZE];

    SysRead(fd, boot_sec, REDSEA_SECTOR_SIZE);
    SysRead(fd, bitmap_sec, REDSEA_SECTOR_SIZE);
    SysRead(fd, dir_sec, REDSEA_SECTOR_SIZE);

    /* Compute 64-bit FNV-1a checksum over all volume bytes */
    SysSeek(fd, 0, VFS_SEEK_SET);
    U64 fnv_hash = 0xcbf29ce484222325ULL;
    U8 cbuf[REDSEA_SECTOR_SIZE];
    I64 rn;
    while ((rn = SysRead(fd, cbuf, REDSEA_SECTOR_SIZE)) > 0) {
        for (I64 i = 0; i < rn; ++i) {
            fnv_hash ^= (U64)cbuf[i];
            fnv_hash *= 0x100000001b3ULL;
        }
    }
    SysClose(fd);

    U16 sig = (U16)(boot_sec[510] | (boot_sec[511] << 8));
    Bool sig_ok = (sig == REDSEA_SIGNATURE);
    Bool oem_ok = (memcmp(boot_sec + 3, "TEMPLEOS", 8) == 0 || memcmp(boot_sec + 3, "REDSEA", 6) == 0);
    I64 total_clusters = st.st_size / REDSEA_SECTOR_SIZE;

    /* Verify reserved clusters 0..2 are marked in bitmap */
    Bool bitmap_ok = RedSeaBitmapGet(bitmap_sec, 0) && RedSeaBitmapGet(bitmap_sec, 1) && RedSeaBitmapGet(bitmap_sec, 2);
    U8 claimed[REDSEA_MAX_CLUSTERS];
    MemSet(claimed, 0, sizeof(claimed));
    claimed[0] = claimed[1] = claimed[2] = 1;

    I64 valid_entries = 0;
    I64 overlaps = 0;
    I64 out_of_bounds = 0;
    I64 entry_count = REDSEA_SECTOR_SIZE / 64;

    for (I64 i = 0; i < entry_count; ++i) {
        CRedSeaDirEntry *entry = (CRedSeaDirEntry*)(dir_sec + (i * 64));
        if (entry->name[0] == '\0') continue;
        valid_entries++;

        I64 nclus = (entry->size > 0) ? ((entry->size + REDSEA_SECTOR_SIZE - 1) / REDSEA_SECTOR_SIZE) : 1;
        if (entry->clus < 3 || entry->size < 0 || entry->clus + nclus > total_clusters || entry->clus + nclus > REDSEA_MAX_CLUSTERS) {
            out_of_bounds++;
            continue;
        }

        for (I64 c = 0; c < nclus; ++c) {
            I64 cid = entry->clus + c;
            if (!RedSeaBitmapGet(bitmap_sec, cid)) {
                bitmap_ok = FALSE;
            }
            if (claimed[cid]) {
                overlaps++;
            }
            claimed[cid] = 1;
        }
    }

    I64 bitmap_allocated = 0;
    for (I64 c = 0; c < total_clusters && c < REDSEA_MAX_CLUSTERS; ++c) {
        if (RedSeaBitmapGet(bitmap_sec, c)) bitmap_allocated++;
    }

    Bool all_valid = (sig_ok && oem_ok && bitmap_ok && overlaps == 0 && out_of_bounds == 0);

    if (json_mode) {
        snprintf(out_buf, max_len,
            "{\"valid\":%s,\"image\":\"%s\",\"signature\":\"0x%04X\",\"total_clusters\":%lld,"
            "\"allocated_clusters\":%lld,\"entries\":%lld,\"bitmap_consistent\":%s,"
            "\"overlaps\":%lld,\"out_of_bounds\":%lld,\"checksum\":\"0x%016llX\"}\n",
            all_valid ? "true" : "false",
            image_path,
            (unsigned int)sig,
            (long long)total_clusters,
            (long long)bitmap_allocated,
            (long long)valid_entries,
            bitmap_ok ? "true" : "false",
            (long long)overlaps,
            (long long)out_of_bounds,
            (unsigned long long)fnv_hash);
    } else {
        snprintf(out_buf, max_len,
            "RedSea Filesystem Check (fsck): %s\n"
            "  Boot Signature     : 0x%04X (%s)\n"
            "  Total Clusters     : %lld (%lld bytes)\n"
            "  Allocated Clusters : %lld\n"
            "  Directory Entries  : %lld\n"
            "  Bitmap Consistency : %s\n"
            "  Cluster Overlaps   : %lld\n"
            "  Bounds Violations  : %lld\n"
            "  Volume FNV-1a Hash : 0x%016llX\n"
            "  Status             : %s\n",
            image_path,
            (unsigned int)sig,
            sig_ok ? "OK" : "CORRUPT",
            (long long)total_clusters,
            (long long)st.st_size,
            (long long)bitmap_allocated,
            (long long)valid_entries,
            bitmap_ok ? "CONSISTENT" : "MISMATCH",
            (long long)overlaps,
            (long long)out_of_bounds,
            (unsigned long long)fnv_hash,
            all_valid ? "CLEAN (VALID REDSEA VOLUME)" : "CORRUPTED");
    }

    return all_valid ? 0 : -1;
}

/* Create a sample RedSea filesystem image for demonstration and testing */
I64 RedSeaCreateSample(const char *target_path) {
    if (!target_path) return -1;

    I64 fd = SysOpen((const U8*)target_path, O_CREAT | O_WRONLY | O_TRUNC);
    if (fd < 0) return -1;

    /* Sector 0: Boot Sector */
    U8 boot_sector[REDSEA_SECTOR_SIZE];
    MemSet(boot_sector, 0, sizeof(boot_sector));
    boot_sector[0] = 0xEB; boot_sector[1] = 0x3C; boot_sector[2] = 0x90; /* jmp short */
    memcpy(boot_sector + 3, "TEMPLEOS", 8);
    boot_sector[11] = 0x00; boot_sector[12] = 0x02; /* 512 bytes / sector */
    boot_sector[13] = 1;                            /* 1 sector / cluster */
    boot_sector[510] = 0xAA; boot_sector[511] = 0x88; /* RedSea signature */
    SysWrite(fd, boot_sector, REDSEA_SECTOR_SIZE);

    /* Sector 1: Cluster Allocation Bitmap */
    U8 bitmap_sector[REDSEA_SECTOR_SIZE];
    MemSet(bitmap_sector, 0, sizeof(bitmap_sector));
    bitmap_sector[0] = 0x3F; /* Clusters 0..5 in use (Boot, Bitmap, RootDir, KERNEL.BIN, ONCE.HC, README.DD) */
    SysWrite(fd, bitmap_sector, REDSEA_SECTOR_SIZE);

    /* Sector 2: Root Directory */
    U8 root_sector[REDSEA_SECTOR_SIZE];
    MemSet(root_sector, 0, sizeof(root_sector));

    CRedSeaDirEntry *e1 = (CRedSeaDirEntry*)(root_sector + 0);
    e1->attr = 0;
    strncpy(e1->name, "KERNEL.BIN", 37);
    e1->clus = 3;
    e1->size = 128;

    CRedSeaDirEntry *e2 = (CRedSeaDirEntry*)(root_sector + 64);
    e2->attr = 0;
    strncpy(e2->name, "ONCE.HC", 37);
    e2->clus = 4;
    e2->size = 64;

    CRedSeaDirEntry *e3 = (CRedSeaDirEntry*)(root_sector + 128);
    e3->attr = 0;
    strncpy(e3->name, "README.DD", 37);
    e3->clus = 5;
    e3->size = 96;

    SysWrite(fd, root_sector, REDSEA_SECTOR_SIZE);

    /* Sector 3: Data for KERNEL.BIN */
    U8 data_sector[REDSEA_SECTOR_SIZE];
    MemSet(data_sector, 0, sizeof(data_sector));
    snprintf((char*)data_sector, sizeof(data_sector),
             "TempleOS 64-Bit HolyC Microkernel Binary (God's Temple Edition)\n");
    SysWrite(fd, data_sector, REDSEA_SECTOR_SIZE);

    /* Sector 4: Data for ONCE.HC */
    MemSet(data_sector, 0, sizeof(data_sector));
    snprintf((char*)data_sector, sizeof(data_sector),
             "\"Welcome to HolyC! God is watching.\\n\";\n");
    SysWrite(fd, data_sector, REDSEA_SECTOR_SIZE);

    /* Sector 5: Data for README.DD */
    MemSet(data_sector, 0, sizeof(data_sector));
    snprintf((char*)data_sector, sizeof(data_sector),
             "$FG,RED$TempleOS RedSea$FG$ document. $BK,1$Divine simplicity.$BK,0$\\n");
    SysWrite(fd, data_sector, REDSEA_SECTOR_SIZE);

    SysClose(fd);
    VFSChmod((const U8*)target_path, "/", 0666);
    return 0;
}

#endif /* REDSEA_HC */
