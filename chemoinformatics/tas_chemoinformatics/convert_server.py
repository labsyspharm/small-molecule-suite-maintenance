from flask import request
from rdkit import Chem, RDLogger
from rdkit.Chem import AllChem, Draw, inchi

from tas_chemoinformatics import app
from .schemas import ConvertIDSchema, ConvertIdResultSchema
from .util import identifier_mol_mapping, mol_identifier_mapping

# Run using:
# FLASK_APP=__init__.py flask run -p 5000
# OR to support multiple parallel requests to speed things up:
# gunicorn --workers=4 -b 127.0.0.1:5000 -t 600 tas_chemoinformatics


@app.route("/convert/identifiers", methods=["POST"])
def convert_ids():
    """Convert compound identifiers.
    ---
    post:
      summary: Convert compound identifiers.
      requestBody:
        required: true
        content:
          application/json:
            schema: ConvertIDSchema
      responses:
        '200':
          content:
            application/json:
              schema: ConvertIdResultSchema
    """
    data = ConvertIDSchema().load(request.json)
    # print(f"Requested conversion of {format_in} to {format_out}")
    mol_in_mapping = identifier_mol_mapping[data["compounds"]["identifier"]]
    mol_out_mapping = mol_identifier_mapping[data["target_identifier"]]
    skipped = []
    compounds_out = {"compounds": [], "identifier": data["target_identifier"]}
    for m in data["compounds"]["compounds"]:
        try:
            mol = mol_in_mapping(m)
            compounds_out["compounds"].append(mol_out_mapping(mol))
        except Exception as e:
            skipped.append(m)
    out = {"compounds": compounds_out, "skipped": skipped}
    ConvertIdResultSchema().validate(out)
    return out
