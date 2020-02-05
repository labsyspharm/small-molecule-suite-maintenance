library(tidyverse)
library(here)
library(synapser)
library(synExtra)
library(vroom)

source(here("id_mapping", "chemoinformatics_funcs.R"))

synLogin()
syn <- synDownloader(here("tempdl"))

release <- "chembl_v25"
dir_release <- here(release)
syn_release <- synFindEntityId(release, "syn18457321")

dir_unichem <- file.path(dir_release, "unichem")

dir.create(dir_unichem, showWarnings = FALSE)

# Download Unichem xref tables -------------------------------------------------
###############################################################################T

unichem_ftp <- "ftp://ftp.ebi.ac.uk/pub/databases/chembl/UniChem/data/oracleDumps/UDRI257/"

download.file(
  file.path(unichem_ftp, "UC_SOURCE.txt.gz"),
  file.path(dir_unichem, "unichem_sources.txt.gz")
)

download.file(
  file.path(unichem_ftp, "UC_XREF.txt.gz"),
  file.path(dir_unichem, "unichem_xref.txt.gz")
)

# system2(
#   "wget",
#   c(
#     "--recursive",
#     "--no-parent",
#     "-q",
#     "-R", "'index.html*'",
#     "-nH",
#     "-P", dir_unichem,
#     "--cut-dirs=6",
#     "ftp://ftp.ebi.ac.uk/pub/databases/chembl/UniChem/data/wholeSourceMapping/src_id1"
#   )
# )

uci_xref <- vroom(
  file.path(dir_unichem, "unichem_xref.txt.gz"),
  col_names = c("uci_old", "src_id", "src_compound_id", "assignment", "last_release_u_when_current", "created", "lastupdated", "userstamp", "aux_src", "uci"),
  col_types = "_ic______i"
)

uci_xref_selected <- uci_xref %>%
  filter(src_id %in% c(1L, 3L, 4L, 7L, 9L, 10L, 14L, 20L, 22L))

unichem_sources <- read_tsv(
  file.path(dir_unichem, "unichem_sources.txt.gz"),
  col_names = c("src_id", "src_name", "date_created", "base_url"),
  col_types = "ic___c_____c______________"
) %>%
  # filter(
  #   src_id %in% c(1L, 3L, 4L, 7L, 9L, 10L, 14L, 20L, 22L)
  # ) %>%
  mutate(xref_type = paste0(src_name, "_id_compound"))


uci_xref_nested <- uci_xref_selected %>%
  group_nest(src_id) %>%
  left_join(unichem_sources, by = "src_id")

chembl_uci <- uci_xref_nested %>%
  filter(src_id == 1L) %>%
  chuck("data", 1) %>%
  rename(chembl_id = src_compound_id)

uci_chembl_mappings <- uci_xref_nested %>%
  filter(src_id != 1L) %>%
  mutate(
    data = map2(
      data, src_name,
      ~.x %>%
        magrittr::set_colnames(recode(colnames(.), src_compound_id = paste0(.y, "_id"))) %>%
        inner_join(
          chembl_uci,
          by = "uci"
        )
    )
  )

write_rds(
  uci_xref_nested,
  file.path(dir_unichem, "unichem_xrefs.rds"),
  compress = "gz"
)

write_rds(
  uci_chembl_mappings,
  file.path(dir_unichem, "chembl_xref_mappings.rds"),
  compress = "gz"
)

pwalk(
  uci_chembl_mappings,
  function(src_name, data, ...) {
    write_csv(
      data,
      file.path(dir_unichem, paste0("chembl_", src_name, "_mapping.csv.gz"))
    )
  }
)

# Xref_total <- unichem_sources %>%
#   mutate(
#     xref_map = map(
#       src_id,
#       function(src_id) {
#         read_tsv(
#           file.path(dir_unichem, "src_id1", paste0("src1src", src_id, ".txt.gz")),
#           col_names = c("chembl_id_compound", "Xref_id_compound"),
#           col_types = "cc",
#           skip = 1
#         )
#       }
#     )
#   ) %>%
#   unnest(xref_map) %>%
#   mutate(url = paste0(base_url, Xref_id_compound))
#
# write_csv(Xref_total, file.path(dir_unichem, "xref_table_unichem.csv.gz"))

# Store to synapse -------------------------------------------------------------
###############################################################################T

unichem_wrangling_activity <- Activity(
  name = "Wrangle Unichem cross-references",
  used = "ftp://ftp.ebi.ac.uk/pub/databases/chembl/UniChem/data/oracleDumps/UDRI257/",
  executed = "https://github.com/clemenshug/small-molecule-suite-maintenance/blob/master/id_mapping/01_unichem_xref_mapping.R"
)

syn_unichem <- Folder("unichem", parent = "syn20830877") %>%
  synStore() %>%
  chuck("properties", "id")

c(
  Sys.glob(file.path(dir_unichem, "chembl_*_mapping.csv.gz")),
  file.path(dir_unichem, "chembl_xref_mappings.rds"),
  file.path(dir_unichem, "unichem_xrefs.rds")
)  %>%
  synStoreMany(parentId = syn_unichem, activity = unichem_wrangling_activity)