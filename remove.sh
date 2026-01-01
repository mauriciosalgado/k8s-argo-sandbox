CONTEXTS=$(cat "contexts.txt")

for ctx in $CONTEXTS; do
  minikube --profile $ctx delete
done
