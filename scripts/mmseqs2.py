from argparse import ArgumentParser
from pathlib import Path
import http.client as httplib
import sys

from colabfold.batch import (get_msa_and_templates,
                             get_queries,
                             msa_to_str)
from colabfold.utils import (DEFAULT_API_SERVER)
# safe_filename moved from colabfold.utils (<= 1.5.x) to colabfold.input (1.6.x)
try:
    from colabfold.input import safe_filename
except ImportError:
    from colabfold.utils import safe_filename

def verifyConnection():
    conn = httplib.HTTPSConnection("8.8.8.8", timeout=5)
    try:
        conn.request("HEAD", "/")
    except:
        conn.close()
        sys.exit(f"Unable to connect to internet, terminating.")
    return True

def main(args):
    connection_verified = False
    result_dir = "mmseqs2_a3m"
    result_dir = Path(result_dir)
    result_dir.mkdir(exist_ok=True)

    queries, is_complex = get_queries(args.query, None)

    print(f"Generating MSAs for {len(queries)} queries")
    for job_number, query in enumerate(queries):
        # get_queries returns (name, sequence, a3m_lines) in ColabFold <= 1.5.x and a 4th element in
        # 1.6.x; only the first three are needed here, so take them by position.
        raw_jobname, query_sequence, a3m_lines = query[:3]
        print(f"{raw_jobname}: {job_number}/{len(queries)}")
        jobname = safe_filename(raw_jobname)
        filepath = result_dir.joinpath(f"{jobname}.a3m")

        if filepath.is_file():
            print(f"Skipping '{jobname}', file already exists: {filepath}")
            continue
        elif connection_verified != True:
            connection_verified = verifyConnection()

        a3m_lines=None
        msa_mode="mmseqs2_uniref_env"
        use_templates=False
        custom_template_path=None
        pair_mode="unpaired"
        host_url=DEFAULT_API_SERVER
        user_agent="fragfold"

        (unpaired_msa,
        paired_msa,
        query_seqs_unique,
        query_seqs_cardinality,
        template_features) \
                        = get_msa_and_templates(jobname=jobname,
                                                query_sequences=query_sequence,
                                                a3m_lines=a3m_lines,
                                                result_dir=result_dir,
                                                msa_mode=msa_mode,
                                                use_templates=use_templates,
                                                custom_template_path=custom_template_path,
                                                pair_mode=pair_mode,
                                                host_url=host_url,
                                                user_agent=user_agent)

        msa = msa_to_str(unpaired_msa, paired_msa, query_seqs_unique, query_seqs_cardinality)
        result_dir.joinpath(f"{jobname}.a3m").write_text(msa)
    print("Done!")

if __name__ == "__main__":
    parser = ArgumentParser()
    parser.add_argument(
        "--query",
        type=Path,
        help="Reads a directory of FASTA files, a single FASTA file or a csv file",
    )
    args = parser.parse_args()
    main(args)
