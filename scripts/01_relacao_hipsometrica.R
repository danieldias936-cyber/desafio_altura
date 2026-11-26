# =============================================================================
# DESAFIO DE DADOS - ALTURA
# Talhao 8, Filial 2 - Eucalipto, clone 1501, idade 7 anos, espacamento 3x3 m
# =============================================================================

library(readxl)
library(writexl)
library(dplyr)
library(ggplot2)
library(minpack.lm)   # nlsLM - ajuste do modelo nao-linear Chapman-Richards

# Executar a partir da raiz do repositorio: Rscript scripts/01_relacao_hipsometrica.R
dir.create("resultados/tabelas", recursive = TRUE, showWarnings = FALSE)
dir.create("resultados/figuras", recursive = TRUE, showWarnings = FALSE)

dados <- read_excel("dados/inventario.xlsx")
dados$HT_medida_flag <- dados$HT > 0


# =============================================================================
# QUESTAO 1 - Identificacao do padrao de amostragem de altura
# =============================================================================

# % de arvores com HT medida, por fileira
tab_fileira <- dados %>%
  group_by(FILEIRA) %>%
  summarise(n = n(), n_medidas = sum(HT_medida_flag),
            pct_medida = 100 * mean(HT_medida_flag))
print(tab_fileira)

# Checagem de excecoes ao padrao esperado (fileiras 3, 4 e 5 = medidas)
fora_das_centrais_com_HT <- dados %>% filter(!(FILEIRA %in% c(3, 4, 5)) & HT > 0)
centrais_sem_HT          <- dados %>% filter(FILEIRA %in% c(3, 4, 5) & HT == 0)
cat("Excecoes fora das fileiras centrais com HT>0:", nrow(fora_das_centrais_com_HT), "\n")
cat("Excecoes dentro das fileiras centrais com HT=0:", nrow(centrais_sem_HT), "\n")
# 0 e 0 -> confirma que a altura foi medida apenas nas fileiras 3, 4 e 5


# =============================================================================
# QUESTAO 2 - Relacao hipsometrica (DAP x HT)
# =============================================================================

medidas <- dados %>% filter(HT > 0)   # n = 109 arvores com HT medida

# Funcoes para comparar modelos na escala original (metros), ja que modelos
# com variavel dependente transformada (ln(HT), 1/HT) nao tem R2 comparavel
# diretamente ao de modelos em HT.
r2_orig  <- function(y, yhat) 1 - sum((y - yhat)^2) / sum((y - mean(y))^2)
aic_orig <- function(y, yhat, k) length(y) * log(sum((y - yhat)^2) / length(y)) + 2 * k

m_linear     <- lm(HT ~ DAP, data = medidas)
m_henricksen <- lm(HT ~ log(DAP), data = medidas)
m_curtis     <- lm(I(1/HT) ~ I(1/DAP), data = medidas)
m_quad       <- lm(HT ~ DAP + I(DAP^2), data = medidas)
m_cr <- nlsLM(HT ~ b0 * (1 - exp(-b1 * DAP))^b2, data = medidas,
              start = list(b0 = 35, b1 = 0.1, b2 = 1.2))

comparacao <- data.frame(
  Modelo = c("Linear", "Henricksen", "Curtis", "Quadratico", "Chapman-Richards"),
  R2 = c(
    r2_orig(medidas$HT, predict(m_linear)),
    r2_orig(medidas$HT, predict(m_henricksen)),
    r2_orig(medidas$HT, 1/predict(m_curtis)),
    r2_orig(medidas$HT, predict(m_quad)),
    r2_orig(medidas$HT, predict(m_cr))
  ),
  AIC = c(
    aic_orig(medidas$HT, predict(m_linear), 3),
    aic_orig(medidas$HT, predict(m_henricksen), 3),
    aic_orig(medidas$HT, 1/predict(m_curtis), 3),
    aic_orig(medidas$HT, predict(m_quad), 4),
    aic_orig(medidas$HT, predict(m_cr), 4)
  )
)
print(comparacao)

# Checagens que motivam a escolha do Chapman-Richards:
cat("Assintota do Curtis (1/coef[1]):", 1/coef(m_curtis)[1], "m (implausivel)\n")
cat("Vertice do quadratico (DAP onde HT passa a CAIR):",
    -coef(m_quad)[2]/(2*coef(m_quad)[3]), "cm\n")
cat("Assintota do Chapman-Richards:", coef(m_cr)["b0"],
    "m (maior HT observada =", max(medidas$HT), "m)\n")

# -> MODELO SELECIONADO: Chapman-Richards (maior R2, menor AIC, assintota
#    biologicamente coerente com a maior altura observada no talhao)
modelo_final <- m_cr
b0 <- coef(m_cr)["b0"]; b1 <- coef(m_cr)["b1"]; b2 <- coef(m_cr)["b2"]

# Diagnostico de residuos do modelo escolhido
shapiro.test(residuals(m_cr))

par(mfrow = c(1, 2))
plot(fitted(m_cr), residuals(m_cr), pch = 19, col = "#2c7a4b",
     xlab = "HT estimada (m)", ylab = "Residuo (m)", main = "Residuos vs. ajustados")
abline(h = 0, col = "#8a3b12", lwd = 2)
qqnorm(residuals(m_cr), pch = 19, col = "#2c7a4b", main = "QQ-plot dos residuos")
qqline(residuals(m_cr), col = "red", lwd = 2)
par(mfrow = c(1, 1))

# Grafico de dispersao com a curva ajustada (entrega obrigatoria)
grafico_hipsometrico <- ggplot(medidas, aes(x = DAP, y = HT)) +
  geom_point(color = "#2c7a4b", alpha = 0.75, size = 2) +
  stat_function(fun = function(x) b0 * (1 - exp(-b1 * x))^b2,
                color = "#8a3b12", linewidth = 1.1) +
  labs(title = "Relacao hipsometrica (Chapman-Richards) - Talhao 8",
       subtitle = paste0("HT = ", round(b0,3), "*(1-exp(-", round(b1,4), "*DAP))^", round(b2,3),
                          "   R2 = ", round(r2_orig(medidas$HT, predict(m_cr)), 4)),
       x = "DAP (cm)", y = "Altura total - HT (m)") +
  theme_minimal()
print(grafico_hipsometrico)
ggsave("resultados/figuras/grafico_hipsometrico.png", grafico_hipsometrico, width = 7, height = 5, dpi = 150, bg = "white")


# =============================================================================
# QUESTAO 3 - Aplicacao do modelo as arvores nao medidas (base completa)
# =============================================================================

dados <- dados %>%
  mutate(
    HT_estimada = b0 * (1 - exp(-b1 * DAP))^b2,
    HT_final    = ifelse(HT > 0, HT, HT_estimada),
    ORIGEM_HT   = ifelse(HT > 0, "medida", "estimada")
  )

# Checagens de sanidade
stopifnot(all(dados$HT_final > 0))
stopifnot(sum(dados$ORIGEM_HT == "medida") == 109)
stopifnot(sum(dados$ORIGEM_HT == "estimada") == 106)
stopifnot(nrow(dados) == 215)

write_xlsx(dados, "resultados/tabelas/inventario_completo.xlsx")


# =============================================================================
# QUESTAO 4 - Altura media e altura dominante por parcela
# =============================================================================

# Altura media: base completa x apenas arvores medidas
comparacao_medias <- dados %>%
  group_by(PARCELA) %>%
  summarise(n_total = n(), HT_media_completa = mean(HT_final)) %>%
  left_join(
    dados %>% filter(HT > 0) %>% group_by(PARCELA) %>%
      summarise(n_medidas = n(), HT_media_so_medidas = mean(HT)),
    by = "PARCELA"
  ) %>%
  mutate(diferenca_m = HT_media_so_medidas - HT_media_completa,
         diferenca_pct = 100 * diferenca_m / HT_media_completa)
print(comparacao_medias)

cat("Media geral (base completa):", mean(dados$HT_final), "\n")
cat("Media geral (so arvores medidas):", mean(dados$HT[dados$HT > 0]), "\n")

# Altura dominante (conceito de Assmann aproximado: ~100 arv/ha mais grossas).
# Espacamento 3x3 m -> densidade teorica 10000/9 = 1111,1 arv/ha ->
# 100 arv/ha equivale a ~9,0% das arvores por parcela (area real da parcela
# nao informada no enunciado; proporcao usada como aproximacao explicita).
prop_assmann <- 100 / (10000 / 9)

Hdom <- dados %>%
  group_by(PARCELA) %>%
  group_modify(~ {
    n_dom <- max(1, round(nrow(.x) * prop_assmann))
    dominantes <- .x %>% arrange(desc(DAP)) %>% slice_head(n = n_dom)
    data.frame(n_dominantes = n_dom, Hdom_m = mean(dominantes$HT_final))
  })
print(Hdom)
cat("Altura dominante media do talhao:", mean(Hdom$Hdom_m), "\n")

# ---- FIM ----
