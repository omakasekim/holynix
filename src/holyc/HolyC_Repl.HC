/*
 * HolyC Unix Kernel - In-Kernel HolyC Interpreter & REPL (HolyC_Repl.HC)
 * Allows users to run HolyC scripts (.HC) and evaluate HolyC statements inside the Unix shell.
 *
 * Implements:
 * 1. Arithmetic expressions, variable assignments, and prints
 * 2. Preprocessor macro engine (#define, #ifdef, #ifndef, #else, #endif)
 * 3. TempleOS inline assembly (asm { ... }) and x86-64 virtual register state
 * 4. Interactive REPL and batch script runner
 */

#ifndef HOLYC_REPL_HC
#define HOLYC_REPL_HC

#include "Types.HC"
#include "VFS.HC"
#include "GodWords.HC"
#include "Terminal.HC"

#define MAX_REPL_VARS 64
#define MAX_REPL_MACROS 32

class CReplVar {
    U8 name[32];
    I64 val;
    Bool is_set;
};

typedef struct {
    char name[32];
    char val[64];
    Bool is_defined;
} CReplMacro;

typedef struct {
    I64 rax;
    I64 rbx;
    I64 rcx;
    I64 rdx;
    I64 rsi;
    I64 rdi;
    I64 rsp;
    I64 rbp;
    I64 rip;
} CReplAsmCpu;

static CReplVar g_repl_vars[MAX_REPL_VARS];
static CReplMacro g_repl_macros[MAX_REPL_MACROS];
static Bool g_preproc_active = TRUE;
static CReplAsmCpu g_asm_cpu = { 0, 0, 0, 0, 0, 0, 0x7FFF0000, 0x7FFF0000, 0x401000 };

U0 ReplInitVars() {
    MemSet(g_repl_vars, 0, sizeof(g_repl_vars));
    MemSet(g_repl_macros, 0, sizeof(g_repl_macros));
    g_preproc_active = TRUE;

    /* Predefine standard HolyC macros */
    strncpy(g_repl_macros[0].name, "__HOLYC__", 31);
    strncpy(g_repl_macros[0].val, "1", 63);
    g_repl_macros[0].is_defined = TRUE;

    strncpy(g_repl_macros[1].name, "TEMPLEOS", 31);
    strncpy(g_repl_macros[1].val, "1", 63);
    g_repl_macros[1].is_defined = TRUE;

    strncpy(g_repl_macros[2].name, "HOLYNIX", 31);
    strncpy(g_repl_macros[2].val, "1", 63);
    g_repl_macros[2].is_defined = TRUE;
}

I64 ReplGetVar(const U8 *name, I64 default_val) {
    for (I64 i = 0; i < MAX_REPL_VARS; ++i) {
        if (g_repl_vars[i].is_set && StrCmp(g_repl_vars[i].name, name) == 0) {
            return g_repl_vars[i].val;
        }
    }
    return default_val;
}

U0 ReplSetVar(const U8 *name, I64 val) {
    for (I64 i = 0; i < MAX_REPL_VARS; ++i) {
        if (g_repl_vars[i].is_set && StrCmp(g_repl_vars[i].name, name) == 0) {
            g_repl_vars[i].val = val;
            return;
        }
    }
    for (I64 i = 0; i < MAX_REPL_VARS; ++i) {
        if (!g_repl_vars[i].is_set) {
            g_repl_vars[i].is_set = TRUE;
            StrNCpy(g_repl_vars[i].name, name, 31);
            g_repl_vars[i].val = val;
            return;
        }
    }
}

Bool ReplIsMacroDefined(const char *name) {
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (g_repl_macros[i].is_defined && strcmp(g_repl_macros[i].name, name) == 0) {
            return TRUE;
        }
    }
    return FALSE;
}

U0 ReplDefineMacro(const char *name, const char *val) {
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (g_repl_macros[i].is_defined && strcmp(g_repl_macros[i].name, name) == 0) {
            strncpy(g_repl_macros[i].val, val ? val : "1", 63);
            return;
        }
    }
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (!g_repl_macros[i].is_defined) {
            g_repl_macros[i].is_defined = TRUE;
            strncpy(g_repl_macros[i].name, name, 31);
            strncpy(g_repl_macros[i].val, val ? val : "1", 63);
            return;
        }
    }
}

U0 ReplUndefMacro(const char *name) {
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (g_repl_macros[i].is_defined && strcmp(g_repl_macros[i].name, name) == 0) {
            g_repl_macros[i].is_defined = FALSE;
            return;
        }
    }
}

const char *ReplGetMacroValue(const char *name) {
    for (int i = 0; i < MAX_REPL_MACROS; ++i) {
        if (g_repl_macros[i].is_defined && strcmp(g_repl_macros[i].name, name) == 0) {
            return g_repl_macros[i].val;
        }
    }
    return NULL;
}

static I64 *ReplResolveAsmReg(const char *name) {
    if (!name) return NULL;
    if (strcasecmp(name, "rax") == 0 || strcasecmp(name, "eax") == 0) return &g_asm_cpu.rax;
    if (strcasecmp(name, "rbx") == 0 || strcasecmp(name, "ebx") == 0) return &g_asm_cpu.rbx;
    if (strcasecmp(name, "rcx") == 0 || strcasecmp(name, "ecx") == 0) return &g_asm_cpu.rcx;
    if (strcasecmp(name, "rdx") == 0 || strcasecmp(name, "edx") == 0) return &g_asm_cpu.rdx;
    if (strcasecmp(name, "rsi") == 0 || strcasecmp(name, "esi") == 0) return &g_asm_cpu.rsi;
    if (strcasecmp(name, "rdi") == 0 || strcasecmp(name, "edi") == 0) return &g_asm_cpu.rdi;
    if (strcasecmp(name, "rsp") == 0 || strcasecmp(name, "esp") == 0) return &g_asm_cpu.rsp;
    if (strcasecmp(name, "rbp") == 0 || strcasecmp(name, "ebp") == 0) return &g_asm_cpu.rbp;
    if (strcasecmp(name, "rip") == 0 || strcasecmp(name, "eip") == 0) return &g_asm_cpu.rip;
    return NULL;
}

/* -------------------------------------------------------------------------
 * Recursive-Descent HolyC Expression Parser with Operator Precedence
 * ------------------------------------------------------------------------- */
typedef struct {
    const char *p;
    int depth;
} CExprParser;

static I64 ReplParseLogicalOr(CExprParser *ep);

static void ReplSkipSpaces(CExprParser *ep) {
    while (*ep->p && isspace((unsigned char)*ep->p)) ep->p++;
}

static I64 ReplParsePrimary(CExprParser *ep) {
    ReplSkipSpaces(ep);
    if (!*ep->p || ep->depth > 64) return 0;

    if (*ep->p == '(') {
        ep->p++;
        ep->depth++;
        I64 val = ReplParseLogicalOr(ep);
        ep->depth--;
        ReplSkipSpaces(ep);
        if (*ep->p == ')') ep->p++;
        return val;
    }

    if (*ep->p == '\'') {
        ep->p++;
        I64 ch = 0;
        if (*ep->p == '\\' && ep->p[1]) {
            ep->p++;
            if (*ep->p == 'n') ch = '\n';
            else if (*ep->p == 't') ch = '\t';
            else if (*ep->p == '0') ch = '\0';
            else ch = (unsigned char)*ep->p;
            ep->p++;
        } else if (*ep->p) {
            ch = (unsigned char)*ep->p++;
        }
        if (*ep->p == '\'') ep->p++;
        return ch;
    }

    /* Hexadecimal literal */
    if (ep->p[0] == '0' && (ep->p[1] == 'x' || ep->p[1] == 'X')) {
        char *endptr = NULL;
        I64 val = (I64)strtoull(ep->p, &endptr, 16);
        if (endptr && endptr > ep->p) ep->p = endptr;
        else ep->p += 2;
        return val;
    }

    /* Binary literal */
    if (ep->p[0] == '0' && (ep->p[1] == 'b' || ep->p[1] == 'B')) {
        ep->p += 2;
        I64 val = 0;
        while (*ep->p == '0' || *ep->p == '1') {
            val = (val << 1) | (*ep->p - '0');
            ep->p++;
        }
        return val;
    }

    /* Decimal literal */
    if (isdigit((unsigned char)*ep->p)) {
        char *endptr = NULL;
        I64 val = (I64)strtoll(ep->p, &endptr, 10);
        if (endptr && endptr > ep->p) ep->p = endptr;
        else ep->p++;
        return val;
    }

    /* Identifier: variable, macro, or CPU register */
    if (isalpha((unsigned char)*ep->p) || *ep->p == '_') {
        char ident[64];
        int vi = 0;
        while (*ep->p && (isalnum((unsigned char)*ep->p) || *ep->p == '_') && vi < 63) {
            ident[vi++] = *ep->p++;
        }
        ident[vi] = '\0';

        if (strcmp(ident, "TRUE") == 0) return 1;
        if (strcmp(ident, "FALSE") == 0) return 0;

        I64 *reg = ReplResolveAsmReg(ident);
        if (reg) return *reg;

        const char *mval = ReplGetMacroValue(ident);
        if (mval) {
            CExprParser sub_ep = { mval, ep->depth + 1 };
            return ReplParseLogicalOr(&sub_ep);
        }

        return ReplGetVar((const U8*)ident, 0);
    }

    return 0;
}

static I64 ReplParseUnary(CExprParser *ep) {
    ReplSkipSpaces(ep);
    if (*ep->p == '-' && ep->p[1] != '-') {
        ep->p++;
        return -ReplParseUnary(ep);
    }
    if (*ep->p == '+' && ep->p[1] != '+') {
        ep->p++;
        return ReplParseUnary(ep);
    }
    if (*ep->p == '~') {
        ep->p++;
        return ~ReplParseUnary(ep);
    }
    if (*ep->p == '!' && ep->p[1] != '=') {
        ep->p++;
        return !ReplParseUnary(ep);
    }
    return ReplParsePrimary(ep);
}

static I64 ReplParseMultiplicative(CExprParser *ep) {
    I64 lhs = ReplParseUnary(ep);
    while (1) {
        ReplSkipSpaces(ep);
        char op = *ep->p;
        if ((op == '*' || op == '/' || op == '%') && ep->p[1] != '=') {
            ep->p++;
            I64 rhs = ReplParseUnary(ep);
            if (op == '*') {
                lhs = (I64)((U64)lhs * (U64)rhs);
            } else if (op == '/') {
                if (rhs == 0) lhs = 0;
                else if (lhs == INT64_MIN && rhs == -1) lhs = INT64_MAX;
                else lhs = lhs / rhs;
            } else {
                if (rhs == 0) lhs = 0;
                else if (lhs == INT64_MIN && rhs == -1) lhs = 0;
                else lhs = lhs % rhs;
            }
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseAdditive(CExprParser *ep) {
    I64 lhs = ReplParseMultiplicative(ep);
    while (1) {
        ReplSkipSpaces(ep);
        char op = *ep->p;
        if ((op == '+' && ep->p[1] != '+' && ep->p[1] != '=') ||
            (op == '-' && ep->p[1] != '-' && ep->p[1] != '=')) {
            ep->p++;
            I64 rhs = ReplParseMultiplicative(ep);
            if (op == '+') lhs = (I64)((U64)lhs + (U64)rhs);
            else lhs = (I64)((U64)lhs - (U64)rhs);
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseShift(CExprParser *ep) {
    I64 lhs = ReplParseAdditive(ep);
    while (1) {
        ReplSkipSpaces(ep);
        if (ep->p[0] == '<' && ep->p[1] == '<') {
            ep->p += 2;
            I64 rhs = ReplParseAdditive(ep);
            if (rhs >= 0 && rhs < 64) lhs = (I64)((U64)lhs << rhs);
            else lhs = 0;
        } else if (ep->p[0] == '>' && ep->p[1] == '>') {
            ep->p += 2;
            I64 rhs = ReplParseAdditive(ep);
            if (rhs >= 0 && rhs < 64) lhs = lhs >> rhs;
            else lhs = 0;
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseRelational(CExprParser *ep) {
    I64 lhs = ReplParseShift(ep);
    while (1) {
        ReplSkipSpaces(ep);
        if (ep->p[0] == '<' && ep->p[1] == '=') {
            ep->p += 2;
            I64 rhs = ReplParseShift(ep);
            lhs = (lhs <= rhs) ? 1 : 0;
        } else if (ep->p[0] == '>' && ep->p[1] == '=') {
            ep->p += 2;
            I64 rhs = ReplParseShift(ep);
            lhs = (lhs >= rhs) ? 1 : 0;
        } else if (ep->p[0] == '<' && ep->p[1] != '<') {
            ep->p += 1;
            I64 rhs = ReplParseShift(ep);
            lhs = (lhs < rhs) ? 1 : 0;
        } else if (ep->p[0] == '>' && ep->p[1] != '>') {
            ep->p += 1;
            I64 rhs = ReplParseShift(ep);
            lhs = (lhs > rhs) ? 1 : 0;
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseEquality(CExprParser *ep) {
    I64 lhs = ReplParseRelational(ep);
    while (1) {
        ReplSkipSpaces(ep);
        if (ep->p[0] == '=' && ep->p[1] == '=') {
            ep->p += 2;
            I64 rhs = ReplParseRelational(ep);
            lhs = (lhs == rhs) ? 1 : 0;
        } else if (ep->p[0] == '!' && ep->p[1] == '=') {
            ep->p += 2;
            I64 rhs = ReplParseRelational(ep);
            lhs = (lhs != rhs) ? 1 : 0;
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseBitAnd(CExprParser *ep) {
    I64 lhs = ReplParseEquality(ep);
    while (1) {
        ReplSkipSpaces(ep);
        if (ep->p[0] == '&' && ep->p[1] != '&' && ep->p[1] != '=') {
            ep->p++;
            I64 rhs = ReplParseEquality(ep);
            lhs = lhs & rhs;
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseBitXor(CExprParser *ep) {
    I64 lhs = ReplParseBitAnd(ep);
    while (1) {
        ReplSkipSpaces(ep);
        if (ep->p[0] == '^' && ep->p[1] != '=') {
            ep->p++;
            I64 rhs = ReplParseBitAnd(ep);
            lhs = lhs ^ rhs;
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseBitOr(CExprParser *ep) {
    I64 lhs = ReplParseBitXor(ep);
    while (1) {
        ReplSkipSpaces(ep);
        if (ep->p[0] == '|' && ep->p[1] != '|' && ep->p[1] != '=') {
            ep->p++;
            I64 rhs = ReplParseBitXor(ep);
            lhs = lhs | rhs;
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseLogicalAnd(CExprParser *ep) {
    I64 lhs = ReplParseBitOr(ep);
    while (1) {
        ReplSkipSpaces(ep);
        if (ep->p[0] == '&' && ep->p[1] == '&') {
            ep->p += 2;
            I64 rhs = ReplParseBitOr(ep);
            lhs = (lhs && rhs) ? 1 : 0;
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplParseLogicalOr(CExprParser *ep) {
    I64 lhs = ReplParseLogicalAnd(ep);
    while (1) {
        ReplSkipSpaces(ep);
        if (ep->p[0] == '|' && ep->p[1] == '|') {
            ep->p += 2;
            I64 rhs = ReplParseLogicalAnd(ep);
            lhs = (lhs || rhs) ? 1 : 0;
        } else {
            break;
        }
    }
    return lhs;
}

static I64 ReplEvalExpr(const U8 *expr) {
    if (!expr) return 0;
    CExprParser ep = { (const char*)expr, 0 };
    return ReplParseLogicalOr(&ep);
}

static I64 g_asm_stack[64];
static I64 g_asm_sp_idx = 0;

/*
 * Evaluates TempleOS inline assembly block: asm { ... }
 */
static U0 ReplEvalAsm(const char *body) {
    Print("\033[93m[HolyC Ring-0 Inline Assembly Evaluator]\033[0m\n");
    char copy[1024];
    strncpy(copy, body, sizeof(copy) - 1);
    copy[sizeof(copy) - 1] = '\0';

    char *saveptr = NULL;
    char *inst = strtok_r(copy, ";\n", &saveptr);
    while (inst) {
        while (*inst && isspace((unsigned char)*inst)) inst++;
        if (*inst && *inst != '}') {
            char op[32] = "", arg1[64] = "", arg2[64] = "";
            const char *p = inst;
            int oi = 0;
            while (*p && !isspace((unsigned char)*p) && oi < 31) op[oi++] = *p++;
            op[oi] = '\0';
            while (*p && isspace((unsigned char)*p)) p++;

            const char *comma = strchr(p, ',');
            if (comma) {
                size_t a1len = comma - p;
                if (a1len > 63) a1len = 63;
                strncpy(arg1, p, a1len);
                arg1[a1len] = '\0';
                while (a1len > 0 && isspace((unsigned char)arg1[a1len - 1])) arg1[--a1len] = '\0';

                const char *p2 = comma + 1;
                while (*p2 && isspace((unsigned char)*p2)) p2++;
                strncpy(arg2, p2, 63);
                arg2[63] = '\0';
                size_t a2len = strlen(arg2);
                while (a2len > 0 && isspace((unsigned char)arg2[a2len - 1])) arg2[--a2len] = '\0';
            } else {
                strncpy(arg1, p, 63);
                arg1[63] = '\0';
                size_t a1len = strlen(arg1);
                while (a1len > 0 && isspace((unsigned char)arg1[a1len - 1])) arg1[--a1len] = '\0';
            }

            if (strcasecmp(op, "nop") == 0) {
                Print("  \033[90m0x%08llX:\033[0m \033[96m90                  \033[0m nop\n",
                      (long long)g_asm_cpu.rip);
                g_asm_cpu.rip += 1;
            } else if (strcasecmp(op, "mov") == 0 && arg1[0] && arg2[0]) {
                I64 *dst = ReplResolveAsmReg(arg1);
                I64 *src_reg = ReplResolveAsmReg(arg2);
                I64 val = src_reg ? *src_reg : ReplEvalExpr((const U8*)arg2);
                if (dst) *dst = val;
                Print("  \033[90m0x%08llX:\033[0m \033[96m48 c7 c0 %02X %02X %02X %02X\033[0m mov %s, 0x%llX\n",
                      (long long)g_asm_cpu.rip,
                      (unsigned int)(val & 0xFF), (unsigned int)((val >> 8) & 0xFF),
                      (unsigned int)((val >> 16) & 0xFF), (unsigned int)((val >> 24) & 0xFF),
                      arg1, (long long)val);
                g_asm_cpu.rip += 7;
            } else if ((strcasecmp(op, "add") == 0 || strcasecmp(op, "sub") == 0 ||
                        strcasecmp(op, "xor") == 0 || strcasecmp(op, "and") == 0 ||
                        strcasecmp(op, "or") == 0  || strcasecmp(op, "imul") == 0 ||
                        strcasecmp(op, "shl") == 0 || strcasecmp(op, "shr") == 0) && arg1[0] && arg2[0]) {
                I64 *dst = ReplResolveAsmReg(arg1);
                I64 *src_reg = ReplResolveAsmReg(arg2);
                I64 val = src_reg ? *src_reg : ReplEvalExpr((const U8*)arg2);
                if (dst) {
                    if (strcasecmp(op, "add") == 0) *dst += val;
                    else if (strcasecmp(op, "sub") == 0) *dst -= val;
                    else if (strcasecmp(op, "xor") == 0) *dst ^= val;
                    else if (strcasecmp(op, "and") == 0) *dst &= val;
                    else if (strcasecmp(op, "or") == 0) *dst |= val;
                    else if (strcasecmp(op, "imul") == 0) *dst *= val;
                    else if (strcasecmp(op, "shl") == 0 && val >= 0 && val < 64) *dst <<= val;
                    else if (strcasecmp(op, "shr") == 0 && val >= 0 && val < 64) *dst = (I64)((U64)(*dst) >> val);
                }
                Print("  \033[90m0x%08llX:\033[0m \033[96m48 83 c0 %02X         \033[0m %s %s, %s\n",
                      (long long)g_asm_cpu.rip, (unsigned int)(val & 0xFF), op, arg1, arg2);
                g_asm_cpu.rip += 4;
            } else if ((strcasecmp(op, "inc") == 0 || strcasecmp(op, "dec") == 0) && arg1[0]) {
                I64 *dst = ReplResolveAsmReg(arg1);
                if (dst) {
                    if (strcasecmp(op, "inc") == 0) (*dst)++;
                    else (*dst)--;
                }
                Print("  \033[90m0x%08llX:\033[0m \033[96m48 ff c0            \033[0m %s %s\n",
                      (long long)g_asm_cpu.rip, op, arg1);
                g_asm_cpu.rip += 3;
            } else if (strcasecmp(op, "push") == 0 && arg1[0]) {
                I64 *src_reg = ReplResolveAsmReg(arg1);
                I64 val = src_reg ? *src_reg : ReplEvalExpr((const U8*)arg1);
                if (g_asm_sp_idx < 64) g_asm_stack[g_asm_sp_idx++] = val;
                g_asm_cpu.rsp -= 8;
                Print("  \033[90m0x%08llX:\033[0m \033[96m50                  \033[0m push %s\n",
                      (long long)g_asm_cpu.rip, arg1);
                g_asm_cpu.rip += 1;
            } else if (strcasecmp(op, "pop") == 0 && arg1[0]) {
                I64 *dst = ReplResolveAsmReg(arg1);
                I64 val = (g_asm_sp_idx > 0) ? g_asm_stack[--g_asm_sp_idx] : 0;
                if (dst) *dst = val;
                g_asm_cpu.rsp += 8;
                Print("  \033[90m0x%08llX:\033[0m \033[96m58                  \033[0m pop %s\n",
                      (long long)g_asm_cpu.rip, arg1);
                g_asm_cpu.rip += 1;
            } else if (strncmp(inst, "int 0x80", 8) == 0) {
                Print("  \033[90m0x%08llX:\033[0m \033[96mcd 80               \033[0m int 0x80 (syscall dispatch)\n",
                      (long long)g_asm_cpu.rip);
                g_asm_cpu.rip += 2;
            } else if (strcasecmp(op, "syscall") == 0) {
                Print("  \033[90m0x%08llX:\033[0m \033[96m0f 05               \033[0m syscall\n",
                      (long long)g_asm_cpu.rip);
                g_asm_cpu.rip += 2;
            } else if (strcasecmp(op, "ret") == 0) {
                Print("  \033[90m0x%08llX:\033[0m \033[96mc3                  \033[0m ret\n",
                      (long long)g_asm_cpu.rip);
                g_asm_cpu.rip += 1;
            } else {
                Print("  \033[90m0x%08llX:\033[0m \033[96m90                  \033[0m %s\n",
                      (long long)g_asm_cpu.rip, inst);
                g_asm_cpu.rip += 1;
            }
        }
        inst = strtok_r(NULL, ";\n", &saveptr);
    }

    Print("  \033[92mRegisters: RAX=0x%llX RBX=0x%llX RCX=0x%llX RDX=0x%llX RIP=0x%llX\033[0m\n",
          (long long)g_asm_cpu.rax, (long long)g_asm_cpu.rbx,
          (long long)g_asm_cpu.rcx, (long long)g_asm_cpu.rdx, (long long)g_asm_cpu.rip);
}

Bool ReplEvalLine(const U8 *raw_line);

static U0 ReplEvalBlock(const char *block_str) {
    if (!block_str || !*block_str) return;
    char buf[1024];
    strncpy(buf, block_str, sizeof(buf) - 1);
    buf[sizeof(buf) - 1] = '\0';

    /* Strip outer braces if present */
    char *p = buf;
    while (*p && isspace((unsigned char)*p)) p++;
    if (*p == '{') {
        p++;
        char *end_b = strrchr(p, '}');
        if (end_b) *end_b = '\0';
    }

    /* Split top-level semicolon statements (respecting quotes and nested braces) */
    char *stmt_start = p;
    int brace_depth = 0;
    int paren_depth = 0;
    Bool in_quote = FALSE;

    for (char *cur = p; ; ++cur) {
        char c = *cur;
        if (c == '"' && (cur == p || *(cur - 1) != '\\')) {
            in_quote = !in_quote;
        } else if (!in_quote) {
            if (c == '{') brace_depth++;
            else if (c == '}') { if (brace_depth > 0) brace_depth--; }
            else if (c == '(') paren_depth++;
            else if (c == ')') { if (paren_depth > 0) paren_depth--; }
        }

        if ((c == ';' && !in_quote && brace_depth == 0 && paren_depth == 0) || c == '\0') {
            char saved = *cur;
            *cur = '\0';
            char *s = stmt_start;
            while (*s && isspace((unsigned char)*s)) s++;
            if (*s) {
                ReplEvalLine((const U8*)s);
            }
            *cur = saved;
            if (c == '\0') break;
            stmt_start = cur + 1;
        }
    }
}

/*
 * Evaluates a single HolyC statement.
 */
Bool ReplEvalLine(const U8 *raw_line) {
    while (*raw_line && isspace((unsigned char)*raw_line)) raw_line++;
    if (!*raw_line || (raw_line[0] == '/' && raw_line[1] == '/')) {
        return TRUE;
    }

    /* Preprocessor directives */
    if (raw_line[0] == '#') {
        const char *cmd = (const char*)raw_line + 1;
        while (*cmd && isspace((unsigned char)*cmd)) cmd++;

        if (strncmp(cmd, "define", 6) == 0) {
            char name[32], val[64] = "1";
            if (sscanf(cmd + 6, "%31s %63s", name, val) >= 1) {
                ReplDefineMacro(name, val);
                Print("\033[90m#define %s %s\033[0m\n", name, val);
            }
            return TRUE;
        } else if (strncmp(cmd, "undef", 5) == 0) {
            char name[32];
            if (sscanf(cmd + 5, "%31s", name) == 1) {
                ReplUndefMacro(name);
            }
            return TRUE;
        } else if (strncmp(cmd, "ifdef", 5) == 0) {
            char name[32];
            if (sscanf(cmd + 5, "%31s", name) == 1) {
                g_preproc_active = ReplIsMacroDefined(name);
            }
            return TRUE;
        } else if (strncmp(cmd, "ifndef", 6) == 0) {
            char name[32];
            if (sscanf(cmd + 6, "%31s", name) == 1) {
                g_preproc_active = !ReplIsMacroDefined(name);
            }
            return TRUE;
        } else if (strncmp(cmd, "else", 4) == 0) {
            g_preproc_active = !g_preproc_active;
            return TRUE;
        } else if (strncmp(cmd, "endif", 5) == 0) {
            g_preproc_active = TRUE;
            return TRUE;
        }
        return TRUE;
    }

    /* If conditional compilation block is inactive, skip execution */
    if (!g_preproc_active) {
        return TRUE;
    }

    U8 line[1024];
    StrNCpy(line, raw_line, sizeof(line) - 1);
    line[sizeof(line) - 1] = '\0';

    /* Strip trailing whitespace and trailing semicolon if not a compound block */
    I64 llen = StrLen(line);
    while (llen > 0 && isspace((unsigned char)line[llen - 1])) {
        line[--llen] = '\0';
    }
    if (llen > 0 && line[llen - 1] == ';' && strchr((char*)line, '{') == NULL) {
        line[--llen] = '\0';
    }

    /* Control flow: if (cond) ... [else ...] */
    if (strncmp((char*)line, "if", 2) == 0 && (isspace((unsigned char)line[2]) || line[2] == '(')) {
        char *lp = strchr((char*)line, '(');
        if (lp) {
            int pdepth = 1;
            char *rp = lp + 1;
            while (*rp && pdepth > 0) {
                if (*rp == '(') pdepth++;
                else if (*rp == ')') pdepth--;
                if (pdepth > 0) rp++;
            }
            if (*rp == ')') {
                char cond_buf[256];
                size_t clen = rp - (lp + 1);
                if (clen > 255) clen = 255;
                strncpy(cond_buf, lp + 1, clen);
                cond_buf[clen] = '\0';

                char *then_start = rp + 1;
                while (*then_start && isspace((unsigned char)*then_start)) then_start++;

                char *else_kw = strstr(then_start, "else");
                char then_buf[512] = "";
                char else_buf[512] = "";
                if (else_kw && (else_kw == then_start || isspace((unsigned char)*(else_kw - 1)) || *(else_kw - 1) == '}' || *(else_kw - 1) == ';')) {
                    size_t tlen = else_kw - then_start;
                    if (tlen > 511) tlen = 511;
                    strncpy(then_buf, then_start, tlen);
                    then_buf[tlen] = '\0';
                    strncpy(else_buf, else_kw + 4, 511);
                    else_buf[511] = '\0';
                } else {
                    strncpy(then_buf, then_start, 511);
                    then_buf[511] = '\0';
                }

                if (ReplEvalExpr((const U8*)cond_buf) != 0) {
                    ReplEvalBlock(then_buf);
                } else if (else_buf[0] != '\0') {
                    ReplEvalBlock(else_buf);
                }
                return TRUE;
            }
        }
    }

    /* Control flow: while (cond) ... */
    if (strncmp((char*)line, "while", 5) == 0 && (isspace((unsigned char)line[5]) || line[5] == '(')) {
        char *lp = strchr((char*)line, '(');
        if (lp) {
            int pdepth = 1;
            char *rp = lp + 1;
            while (*rp && pdepth > 0) {
                if (*rp == '(') pdepth++;
                else if (*rp == ')') pdepth--;
                if (pdepth > 0) rp++;
            }
            if (*rp == ')') {
                char cond_buf[256];
                size_t clen = rp - (lp + 1);
                if (clen > 255) clen = 255;
                strncpy(cond_buf, lp + 1, clen);
                cond_buf[clen] = '\0';
                char *body_start = rp + 1;
                int max_iters = 1024;
                while (max_iters-- > 0 && ReplEvalExpr((const U8*)cond_buf) != 0) {
                    ReplEvalBlock(body_start);
                }
                return TRUE;
            }
        }
    }

    /* Control flow: for (init; cond; step) ... */
    if (strncmp((char*)line, "for", 3) == 0 && (isspace((unsigned char)line[3]) || line[3] == '(')) {
        char *lp = strchr((char*)line, '(');
        if (lp) {
            int pdepth = 1;
            char *rp = lp + 1;
            while (*rp && pdepth > 0) {
                if (*rp == '(') pdepth++;
                else if (*rp == ')') pdepth--;
                if (pdepth > 0) rp++;
            }
            if (*rp == ')') {
                char header[256];
                size_t hlen = rp - (lp + 1);
                if (hlen > 255) hlen = 255;
                strncpy(header, lp + 1, hlen);
                header[hlen] = '\0';

                char *s1 = strchr(header, ';');
                char *s2 = s1 ? strchr(s1 + 1, ';') : NULL;
                if (s1 && s2) {
                    *s1 = '\0';
                    *s2 = '\0';
                    const char *init_stmt = header;
                    const char *cond_expr = s1 + 1;
                    const char *step_stmt = s2 + 1;
                    const char *body_start = rp + 1;

                    if (*init_stmt) ReplEvalLine((const U8*)init_stmt);
                    int max_iters = 1024;
                    while (max_iters-- > 0 && (!*cond_expr || ReplEvalExpr((const U8*)cond_expr) != 0)) {
                        ReplEvalBlock(body_start);
                        if (*step_stmt) ReplEvalLine((const U8*)step_stmt);
                    }
                    return TRUE;
                }
            }
        }
    }

    /* Inline Assembly: asm { ... } or _asm { ... } */
    if (strncmp((char*)line, "asm", 3) == 0 || strncmp((char*)line, "_asm", 4) == 0) {
        char *brace = strchr((char*)line, '{');
        if (brace) {
            char *end_brace = strrchr(brace, '}');
            if (end_brace) *end_brace = '\0';
            ReplEvalAsm(brace + 1);
            return TRUE;
        }
    }

    /* Exit command */
    if (StrCmp(line, "Exit") == 0 || StrCmp(line, "exit") == 0 || StrCmp(line, "quit") == 0) {
        return FALSE;
    }

    /* Bare HolyC commands */
    if (StrCmp(line, "God") == 0 || StrCmp(line, "God;") == 0) {
        GodSpeak(7);
        return TRUE;
    }
    if (StrCmp(line, "Clear") == 0) {
        TermClearScreen();
        return TRUE;
    }
    if (StrCmp(line, "Uptime") == 0) {
        Print("Uptime: %lld seconds, %lld ticks\n",
              (long long)KernelGetUptimeSec(), (long long)KernelGetTicks());
        return TRUE;
    }

    /* HolyC Print statement: starts with '"' */
    if (line[0] == '"') {
        /* Find closing quote (respecting escaped quotes) */
        char *close_quote = (char*)line + 1;
        while (*close_quote && !(*close_quote == '"' && *(close_quote - 1) != '\\')) {
            close_quote++;
        }
        if (*close_quote == '"') {
            *close_quote = '\0';
            const char *fmt = (char*)line + 1;
            const char *args = close_quote + 1;
            while (*args && (*args == ' ' || *args == ',')) args++;

            /* Parse comma-separated argument expressions */
            I64 arg_vals[16];
            int arg_count = 0;
            if (*args != '\0') {
                const char *ap = args;
                while (*ap && arg_count < 16) {
                    while (*ap && isspace((unsigned char)*ap)) ap++;
                    if (!*ap) break;
                    const char *start = ap;
                    int pdepth = 0;
                    while (*ap) {
                        if (*ap == '(') pdepth++;
                        else if (*ap == ')') { if (pdepth > 0) pdepth--; }
                        else if (*ap == ',' && pdepth == 0) break;
                        ap++;
                    }
                    char expr_buf[256];
                    size_t elen = ap - start;
                    if (elen > 255) elen = 255;
                    strncpy(expr_buf, start, elen);
                    expr_buf[elen] = '\0';
                    arg_vals[arg_count++] = ReplEvalExpr((const U8*)expr_buf);
                    if (*ap == ',') ap++;
                }
            }

            int arg_idx = 0;
            for (int i = 0; fmt[i]; ++i) {
                if (fmt[i] == '\\' && fmt[i + 1] == 'n') {
                    Print("\n");
                    i++;
                } else if (fmt[i] == '\\' && fmt[i + 1] == 't') {
                    Print("\t");
                    i++;
                } else if (fmt[i] == '%' && fmt[i + 1] == '%') {
                    PutChars('%');
                    i++;
                } else if (fmt[i] == '%' && fmt[i + 1] != '\0') {
                    i++;
                    /* Skip optional width/long specifiers */
                    while (fmt[i] && (isdigit((unsigned char)fmt[i]) || fmt[i] == 'l' || fmt[i] == '-' || fmt[i] == '+')) {
                        i++;
                    }
                    I64 v = (arg_idx < arg_count) ? arg_vals[arg_idx++] : 0;
                    if (fmt[i] == 'x') Print("%llx", (unsigned long long)v);
                    else if (fmt[i] == 'X') Print("%llX", (unsigned long long)v);
                    else if (fmt[i] == 'u') Print("%llu", (unsigned long long)v);
                    else if (fmt[i] == 'c') PutChars((int)v);
                    else Print("%lld", (long long)v);
                } else {
                    PutChars(fmt[i]);
                }
            }
            return TRUE;
        }
    }

    /* Strip type prefix: I64, U64, I32, U32, I16, U16, I8, U8, U0, Bool */
    const char *p = (const char*)line;
    if (strncmp(p, "I64 ", 4) == 0 || strncmp(p, "U64 ", 4) == 0 ||
        strncmp(p, "I32 ", 4) == 0 || strncmp(p, "U32 ", 4) == 0 ||
        strncmp(p, "I16 ", 4) == 0 || strncmp(p, "U16 ", 4) == 0 ||
        strncmp(p, "Bool ", 5) == 0 || strncmp(p, "U0 ", 3) == 0 ||
        strncmp(p, "U8 ", 3) == 0  || strncmp(p, "I8 ", 3) == 0) {
        p = strchr(p, ' ') + 1;
    }
    while (*p && isspace((unsigned char)*p)) p++;

    /* Check ++ or -- */
    size_t plen = strlen(p);
    if (plen > 2 && ((p[plen - 2] == '+' && p[plen - 1] == '+') || (p[plen - 2] == '-' && p[plen - 1] == '-'))) {
        char vname[32];
        size_t vlen = plen - 2;
        if (vlen > 31) vlen = 31;
        strncpy(vname, p, vlen);
        vname[vlen] = '\0';
        while (vlen > 0 && isspace((unsigned char)vname[vlen - 1])) vname[--vlen] = '\0';
        I64 cur = ReplGetVar((const U8*)vname, 0);
        I64 next = (p[plen - 1] == '+') ? (cur + 1) : (cur - 1);
        ReplSetVar((const U8*)vname, next);
        Print("\033[90m%s = %lld\033[0m\n", vname, (long long)next);
        return TRUE;
    }

    /* Check assignment (=, +=, -=, *=, /=, %=), avoiding ==, !=, <=, >= */
    const char *eq = NULL;
    char compound_op = 0;
    for (const char *scan = p; *scan; ++scan) {
        if (*scan == '=') {
            if (scan[1] == '=') { scan++; continue; }
            if (scan > p && (scan[-1] == '!' || scan[-1] == '<' || scan[-1] == '>')) {
                continue;
            }
            if (scan > p && (scan[-1] == '+' || scan[-1] == '-' || scan[-1] == '*' || scan[-1] == '/' || scan[-1] == '%')) {
                compound_op = scan[-1];
            }
            eq = scan;
            break;
        }
    }

    if (eq) {
        char vname[32];
        int vi = 0;
        const char *vp = p;
        const char *vend = compound_op ? (eq - 1) : eq;
        while (vp < vend && (isalnum((unsigned char)*vp) || *vp == '_') && vi < 31) {
            vname[vi++] = *vp++;
        }
        vname[vi] = '\0';
        I64 rhs = ReplEvalExpr((const U8*)(eq + 1));
        I64 val = rhs;
        if (compound_op) {
            I64 cur = ReplGetVar((const U8*)vname, 0);
            if (compound_op == '+') val = cur + rhs;
            else if (compound_op == '-') val = cur - rhs;
            else if (compound_op == '*') val = cur * rhs;
            else if (compound_op == '/') val = (rhs != 0) ? (cur / rhs) : 0;
            else if (compound_op == '%') val = (rhs != 0) ? (cur % rhs) : 0;
        }
        ReplSetVar((const U8*)vname, val);
        Print("\033[90m%s = %lld\033[0m\n", vname, (long long)val);
        return TRUE;
    }

    /* If it's an expression, evaluate and print */
    I64 eval_res = ReplEvalExpr((const U8*)line);
    Print("\033[92m%lld\033[0m\n", (long long)eval_res);
    return TRUE;
}

U0 HolyCEvalString(const char *code) {
    if (!code || !*code) return;
    ReplInitVars();
    ReplEvalBlock(code);
}

U0 HolyCRunScript(const U8 *path) {
    CTask *t = TaskGetCurrent();
    const U8 *cwd = t ? t->cwd : (const U8*)"/";
    I64 fd = VFSOpen(path, cwd, O_RDONLY);
    if (fd < 0) {
        Print("\033[91mError: Cannot open HolyC script '%s'\033[0m\n", path);
        return;
    }

    U8 chunk[8192];
    I64 bytes_read = VFSRead(fd, chunk, sizeof(chunk) - 1);
    VFSClose(fd);
    if (bytes_read <= 0) {
        Print("\033[90m[Empty script]\033[0m\n");
        return;
    }
    chunk[bytes_read] = '\0';

    char *saveptr = NULL;
    char *line = strtok_r((char*)chunk, "\r\n", &saveptr);
    while (line) {
        ReplEvalLine((const U8*)line);
        line = strtok_r(NULL, "\r\n", &saveptr);
    }
}

U0 HolyCRepl() {
    ReplInitVars();
    Print("\033[93m====================================================\033[0m\n");
    Print("\033[96mHolyC Interactive REPL v0.2.0 (TempleOS Environment)\033[0m\n");
    Print("\033[90mType HolyC statements, \"String\\n\";, God;, or Exit;\033[0m\n");
    Print("\033[93m====================================================\033[0m\n");

    U8 line[256];
    while (1) {
        I64 n = TermReadLine(line, sizeof(line), (const U8*)"\033[95mHolyC>\033[0m ");
        if (n < 0) break;
        if (n == 0) continue;
        if (!ReplEvalLine(line)) {
            break;
        }
    }
    Print("\033[90m[Exited HolyC REPL]\033[0m\n");
}

#endif /* HOLYC_REPL_HC */
