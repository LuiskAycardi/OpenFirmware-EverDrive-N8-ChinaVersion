/* nucleo.c — lógica del mando emulado: guion de botones, fotogramas por LATCH y protocolo con el PC.
 *
 * FOTOGRAMAS. El número de fotograma sigue la numeración del banco de pruebas (run_test.lua: fotogramas
 * completos desde el encendido). Un LATCH que llega al menos medio periodo después del que abrió el fotograma
 * actual abre otro. Si el juego se salta lecturas (fotogramas de carga), los fotogramas que faltan se cuentan
 * por tiempo: el LATCH que llega entre (k - 1/2) y (k + 1/2) periodos después es el fotograma actual + k. El
 * periodo (NTSC, ~16,64 ms) se mide de los propios LATCH. Con "A p0" el número se fija a p0 en el primer LATCH
 * después de un silencio (el juego recién arrancado por el OS); p0 es el primer fotograma en que el juego lee el
 * mando en el banco.
 *
 * BYTE DE CADA LECTURA. El byte se prepara antes de que llegue el LATCH: en la primera mitad del fotograma, el
 * del propio fotograma (para juegos que leen el mando dos veces); a partir de la mitad, el del siguiente. Así el
 * hardware solo tiene que copiarlo.
 *
 * Protocolo (líneas de texto; cada orden recibe una línea "ok ..." o "error ..."; los avisos empiezan por "!"):
 *   ?                   ok N8MANDO 1
 *   E                   ok fc= val= lat= per16= man= tramos= arm= sil= v5= miso= perd=
 *   Z n | X             fija el fotograma actual (y activa el guion) | desactiva el guion
 *   B hh | P bot | S [bot]   botones fijos: máscara hex | pulsar | soltar (sin nada: todos)
 *   T bot ms            pulsar durante ms y soltar           -> !T
 *   R [ms]              Select+B (reset del kit Lava) hasta ms (5000) o hasta ver el reset -> !R reset= lat=
 *   GB | GA tramos      borrar el guion | añadir "ini-fin:bot+bot;..." (formato de N8_SCRIPT)
 *   A p0 [ms]           armar: en el primer LATCH tras ms (250) de silencio, fotograma = p0 -> !INICIO fc=
 *   L 0|1               aviso "!L fc" en cada fotograma nuevo
 * Botones: a b select start up down left right, unidos con '+'.
 */
#include "nucleo.h"

#define PER16_NTSC 66557u                  /* 16 x 16639,3 µs / 4 µs */
#define SILENCIO_MISO (500ul * TICKS_MS)   /* sin lecturas 0,5 s: DATA en alta impedancia */
#define MAX_TRAMOS 64
#define LINEA_MAX 120

enum { BA = 0x01, BB = 0x02, BSEL = 0x04, BSTA = 0x08 };

typedef struct { uint32_t ini, fin; uint8_t m; } tramo_t;

static tramo_t tramos[MAX_TRAMOS];
static uint8_t n_tramos;
static uint32_t fin_guion;
static uint8_t fin_avisado;

static uint32_t fc;          /* fotograma actual */
static uint8_t fc_valido;    /* el guion se aplica */
static uint32_t t_foto;      /* LATCH que abrió el fotograma actual */
static uint32_t t_sig;       /* próxima frontera: t_foto + (k_pend + 1/2) periodos */
static uint32_t k_pend;      /* fronteras cruzadas desde t_foto */
static uint32_t t_ult;       /* último LATCH */
static uint32_t per16 = PER16_NTSC;
static uint32_t n_latch;
static uint8_t manual;
static uint8_t eventos;
static uint8_t miso;

static uint8_t armado, arm_cargado;
static uint32_t arm_p0, arm_sil;

static uint8_t pulso;        /* 0, 'T' o 'R' */
static uint8_t pulso_m, pulso_reset;
static uint32_t pulso_t0, pulso_fin, pulso_lat0;

static char linea[LINEA_MAX + 1];
static uint8_t n_linea, desborde;

/* ---------------------------------------------------------------- salida (sin multiplicar ni dividir:
   el AVR no tiene división y así no hacen falta rutinas de libgcc) */
static void tx_s(const char *s) { while (*s) hw_tx((uint8_t)*s++); }

static uint32_t divu(uint32_t n, uint32_t d, uint32_t *resto) {
    uint32_t q = 0, r = 0;
    for (uint8_t i = 0; i < 32; i++) {
        r = (r << 1) | (n >> 31);
        n <<= 1;
        q <<= 1;
        if (r >= d) { r -= d; q |= 1; }
    }
    *resto = r;
    return q;
}

static void tx_u(uint32_t v) {
    char b[10];
    uint8_t i = 0;
    do { uint32_t r; v = divu(v, 10, &r); b[i++] = (char)('0' + r); } while (v);
    while (i) hw_tx((uint8_t)b[--i]);
}

static void tx_h(uint8_t v) {
    static const char h[] = "0123456789abcdef";
    hw_tx((uint8_t)h[v >> 4]);
    hw_tx((uint8_t)h[v & 15]);
}

static void tx_kv(const char *k, uint32_t v) { hw_tx(' '); tx_s(k); hw_tx('='); tx_u(v); }

static uint32_t ms_ticks(uint32_t ms) {          /* ms x 250 = ms x 256 - ms x 4 - ms x 2 */
    return (ms << 8) - (ms << 2) - (ms << 1);
}

/* ---------------------------------------------------------------- botones */
static uint8_t guion(uint32_t f) {               /* el primer tramo que contiene f, como run_test.lua */
    for (uint8_t i = 0; i < n_tramos; i++)
        if (f >= tramos[i].ini && f <= tramos[i].fin) return tramos[i].m;
    return 0;
}

static uint8_t botones(uint32_t f) {
    uint8_t m = manual | pulso_m;
    if (fc_valido) m |= guion(f);
    return m;
}

static uint8_t arm_esperando(void) { return armado && arm_cargado; }

static void recargar(void) {                      /* byte para la próxima lectura */
    if (arm_esperando()) hw_cargar((uint8_t)~(manual | pulso_m | guion(arm_p0)));
    else hw_cargar((uint8_t)~botones(fc + k_pend));
}

static void fronteras(uint32_t t) {
    while ((int32_t)(t - t_sig) >= 0) {
        k_pend++;
        t_sig += per16 >> 4;
        if (!arm_esperando()) hw_cargar((uint8_t)~botones(fc + k_pend));
    }
}

static void nuevo_inicio(uint32_t t) {
    t_foto = t;
    k_pend = 0;
    t_sig = t + (per16 >> 5);
}

/* ---------------------------------------------------------------- eventos del hardware */
void nucleo_inicio(uint32_t t) {
    t_ult = t;
    nuevo_inicio(t);
    hw_cargar(0xFF);
    tx_s("!HOLA N8MANDO 1\n");
}

void nucleo_latch(uint32_t t) {
    uint32_t sil = t - t_ult;
    t_ult = t;
    n_latch++;
    miso = 1;                                      /* la interrupción ya ha puesto MISO como salida */
    if (armado && sil >= arm_sil) {
        armado = arm_cargado = 0;
        fc = arm_p0;
        fc_valido = 1;
        fin_avisado = 0;
        nuevo_inicio(t);
        recargar();
        tx_s("!INICIO");
        tx_kv("fc", fc);
        hw_tx('\n');
        return;
    }
    fronteras(t);
    if (k_pend == 0) return;                       /* otra lectura en el mismo fotograma */
    uint32_t dt = t - t_foto;
    if (k_pend == 1 && dt < (per16 >> 3)) {        /* afina el periodo con fotogramas consecutivos */
        int32_t e = (int32_t)(dt << 4) - (int32_t)per16;
        int32_t lim = (int32_t)(per16 >> 2);
        if (e > -lim && e < lim) per16 = (uint32_t)((int32_t)per16 + (e >> 5));
    }
    fc += k_pend;
    nuevo_inicio(t);
    recargar();
    if (eventos) { tx_s("!L "); tx_u(fc); hw_tx('\n'); }
    if (fc_valido && n_tramos && !fin_avisado && fc > fin_guion) {
        fin_avisado = 1;
        tx_s("!FIN");
        tx_kv("fc", fc);
        hw_tx('\n');
    }
}

void nucleo_tick(uint32_t t) {
    if (armado && !arm_cargado && (t - t_ult) >= arm_sil) {
        arm_cargado = 1;
        recargar();
    }
    fronteras(t);
    if (miso && (t - t_ult) >= SILENCIO_MISO) {
        miso = 0;
        hw_miso(0);
    }
    if (pulso) {
        /* Reset del kit: tras 2,5 s pulsando, un silencio de 200 ms en un juego que leía = consola reseteada */
        if (pulso == 'R' && !pulso_reset && n_latch != pulso_lat0 && (t - pulso_t0) >= ms_ticks(2500) &&
            (t - t_ult) >= ms_ticks(200))
            pulso_reset = 1;
        if (pulso_reset || (int32_t)(t - pulso_fin) >= 0) {
            uint8_t tipo = pulso;
            pulso = 0;
            pulso_m = 0;
            recargar();
            if (tipo == 'R') {
                tx_s("!R");
                tx_kv("reset", pulso_reset);
                tx_kv("lat", n_latch - pulso_lat0);
            } else {
                tx_s("!T");
            }
            hw_tx('\n');
        }
    }
}

/* ---------------------------------------------------------------- órdenes */
static void saltar(const char **p) { while (**p == ' ') (*p)++; }

static uint8_t numero(const char **p, uint32_t *v) {
    saltar(p);
    if (**p < '0' || **p > '9') return 0;
    uint32_t x = 0;
    while (**p >= '0' && **p <= '9') { x = (x << 3) + (x << 1) + (uint32_t)(**p - '0'); (*p)++; }
    *v = x;
    return 1;
}

static uint8_t hex8(const char **p, uint8_t *v) {
    saltar(p);
    uint8_t x = 0, n = 0;
    for (;;) {
        char c = **p;
        uint8_t d;
        if (c >= '0' && c <= '9') d = (uint8_t)(c - '0');
        else if (c >= 'a' && c <= 'f') d = (uint8_t)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') d = (uint8_t)(c - 'A' + 10);
        else break;
        x = (uint8_t)((x << 4) | d);
        n++;
        (*p)++;
    }
    *v = x;
    return n > 0 && n <= 2;
}

static uint8_t igual(const char *a, uint8_t n, const char *b) {
    for (uint8_t i = 0; i < n; i++) if (a[i] != b[i]) return 0;
    return b[n] == 0;
}

/* "a+b+start": devuelve 1 si todos los nombres existen */
static uint8_t mascara(const char **p, uint8_t *m) {
    static const char *const nombres[8] = { "a", "b", "select", "start", "up", "down", "left", "right" };
    saltar(p);
    *m = 0;
    for (;;) {
        const char *ini = *p;
        while ((**p >= 'a' && **p <= 'z') || (**p >= 'A' && **p <= 'Z')) (*p)++;
        uint8_t n = (uint8_t)(*p - ini), ok = 0;
        if (n == 0) return 0;
        char low[8];
        if (n > 7) return 0;
        for (uint8_t i = 0; i < n; i++) low[i] = (char)(ini[i] | 0x20);
        for (uint8_t b = 0; b < 8; b++)
            if (igual(low, n, nombres[b])) { *m |= (uint8_t)(1u << b); ok = 1; }
        if (!ok) return 0;
        if (**p != '+') return 1;
        (*p)++;
    }
}

static void ok(void) { tx_s("ok\n"); }
static void error(const char *s) { tx_s("error "); tx_s(s); hw_tx('\n'); }

static void anadir_tramos(const char *p) {
    for (;;) {
        uint32_t a, b;
        uint8_t m;
        saltar(&p);
        if (*p == 0) break;
        if (!numero(&p, &a) || *p++ != '-' || !numero(&p, &b) || *p++ != ':' || !mascara(&p, &m) || b < a) {
            error("formato");
            return;
        }
        if (n_tramos >= MAX_TRAMOS) { error("lleno"); return; }
        tramos[n_tramos].ini = a;
        tramos[n_tramos].fin = b;
        tramos[n_tramos].m = m;
        n_tramos++;
        if (b > fin_guion) fin_guion = b;
        fin_avisado = 0;
        saltar(&p);
        if (*p == ';') p++;
    }
    recargar();
    tx_s("ok");
    tx_kv("n", n_tramos);
    hw_tx('\n');
}

static void estado(uint32_t t) {
    tx_s("ok");
    tx_kv("fc", fc);
    tx_kv("val", fc_valido);
    tx_kv("lat", n_latch);
    tx_kv("per16", per16);
    tx_s(" man=");
    tx_h(manual);
    tx_kv("tramos", n_tramos);
    tx_kv("arm", armado);
    uint32_t r;
    tx_kv("sil", divu(t - t_ult, TICKS_MS, &r));
    tx_kv("v5", hw_v5());
    tx_kv("miso", miso);
    tx_kv("perd", hw_perdidos());
    hw_tx('\n');
}

static void ejecutar(const char *s, uint32_t t) {
    const char *p = s + 1;
    uint32_t v;
    uint8_t m;
    switch (s[0]) {
    case '?': tx_s("ok N8MANDO 1\n"); break;
    case 'E': estado(t); break;
    case 'Z':
        if (!numero(&p, &v)) { error("numero"); break; }
        fc = v; fc_valido = 1; fin_avisado = 0; armado = arm_cargado = 0;
        nuevo_inicio(t);
        recargar(); ok();
        break;
    case 'X': fc_valido = 0; armado = arm_cargado = 0; recargar(); ok(); break;
    case 'B':
        if (!hex8(&p, &m)) { error("hex"); break; }
        manual = m; recargar(); ok();
        break;
    case 'P':
        if (!mascara(&p, &m)) { error("boton"); break; }
        manual |= m; recargar(); ok();
        break;
    case 'S':
        saltar(&p);
        if (*p == 0) manual = 0;
        else if (mascara(&p, &m)) manual &= (uint8_t)~m;
        else { error("boton"); break; }
        recargar(); ok();
        break;
    case 'T':
        if (!mascara(&p, &m) || !numero(&p, &v)) { error("formato"); break; }
        pulso = 'T'; pulso_m = m; pulso_reset = 0; pulso_t0 = t; pulso_fin = t + ms_ticks(v);
        recargar(); ok();
        break;
    case 'R':
        if (!numero(&p, &v)) v = 5000;
        pulso = 'R'; pulso_m = BSEL | BB; pulso_reset = 0; pulso_t0 = t; pulso_fin = t + ms_ticks(v);
        pulso_lat0 = n_latch;
        recargar(); ok();
        break;
    case 'G':
        if (s[1] == 'B') { n_tramos = 0; fin_guion = 0; recargar(); ok(); }
        else if (s[1] == 'A') anadir_tramos(s + 2);
        else error("orden");
        break;
    case 'A':
        if (!numero(&p, &v)) { error("numero"); break; }
        arm_p0 = v;
        arm_sil = ms_ticks(numero(&p, &v) ? v : 250);
        armado = 1; arm_cargado = 0; fc_valido = 0;
        recargar(); ok();
        break;
    case 'L':
        eventos = (uint8_t)(numero(&p, &v) && v);
        ok();
        break;
    default: error("orden");
    }
}

void nucleo_rx(uint8_t c, uint32_t t) {
    if (c == '\r') return;
    if (c == '\n') {
        linea[n_linea] = 0;
        if (desborde) error("larga");
        else if (n_linea) ejecutar(linea, t);
        n_linea = 0;
        desborde = 0;
        return;
    }
    if (n_linea < LINEA_MAX) linea[n_linea++] = (char)c;
    else desborde = 1;
}
