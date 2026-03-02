# Agenix secrets configuration
# Maps encrypted files to the public keys that can decrypt them
let
  users = {
    j_kro = "age1p98yp8w64rdugp03332gxnz5q2vcnucn69cs5qm6s2l2u7epqfcqmu2pqe";
  };
in
{
  "huggingface-token.age".publicKeys = [users.j_kro];
}
