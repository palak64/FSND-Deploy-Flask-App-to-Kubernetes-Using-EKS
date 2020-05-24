# Deploying a Flask API

This is the project starter repo for the fourth course in the [Udacity Full Stack Nanodegree](https://www.udacity.com/course/full-stack-web-developer-nanodegree--nd004): Server Deployment, Containerization, and Testing.

In this project you will containerize and deploy a Flask API to a Kubernetes cluster using Docker, AWS EKS, CodePipeline, and CodeBuild.

The Flask app that will be used for this project consists of a simple API with three endpoints:

- `GET '/'`: This is a simple health check, which returns the response 'Healthy'. 
- `POST '/auth'`: This takes a email and password as json arguments and returns a JWT based on a custom secret.
- `GET '/contents'`: This requires a valid JWT, and returns the un-encrpyted contents of that token. 

The app relies on a secret set as the environment variable `JWT_SECRET` to produce a JWT. The built-in Flask server is adequate for local development, but not production, so you will be using the production-ready [Gunicorn](https://gunicorn.org/) server when deploying the app.

## Initial setup
1. Fork this project to your Github account.
2. Locally clone your forked version to begin working on the project.

## Dependencies

- Docker Engine
    - Installation instructions for all OSes can be found [here](https://docs.docker.com/install/).
    - For Mac users, if you have no previous Docker Toolbox installation, you can install Docker Desktop for Mac. If you already have a Docker Toolbox installation, please read [this](https://docs.docker.com/docker-for-mac/docker-toolbox/) before installing.
 - AWS Account
     - You can create an AWS account by signing up [here](https://aws.amazon.com/#).
     
## Project Steps

Completing the project involves several steps:

1. Write a Dockerfile for a simple Flask API
2. Build and test the container locally
3. Create an EKS cluster
4. Store a secret using AWS Parameter Store
5. Create a CodePipeline pipeline triggered by GitHub checkins
6. Create a CodeBuild stage which will build, test, and deploy your code

For more detail about each of these steps, see the project lesson [here](https://classroom.udacity.com/nanodegrees/nd004/parts/1d842ebf-5b10-4749-9e5e-ef28fe98f173/modules/ac13842f-c841-4c1a-b284-b47899f4613d/lessons/becb2dac-c108-4143-8f6c-11b30413e28d/concepts/092cdb35-28f7-4145-b6e6-6278b8dd7527).

### Testing Locally
```
export TOKEN=`curl -d '{"email":"<EMAIL>","password":"<PASSWORD>"}' -H "Content-Type: application/json" -X POST localhost:8080/auth  | jq -r '.token'`
curl --request GET 'http://127.0.0.1:8080/contents' -H "Authorization: Bearer ${TOKEN}" | jq .
```

### Containerize the Flask App and Run Locally

1. Create a Dockerfile named Dockerfile in the app repo. Your Dockerfile should:
    -Use the python:stretch image as a source image
    -Set up an app directory for your code
    -Install needed Python requirements
    -Define an entrypoint which will run the main app using the Gunicorn WSGI server
    
2. Create a file named env_file and use it to set the environment variables which will be run locally in your container. Here, we do not    need the export command, just an equals sign: 
    ```
    <VARIABLE_NAME>=<VARIABLE_VALUE>
    ```
    In this file, you should set both JWT_SECRET and LOG_LEVEL, similar to how they were set as environment variables when you ran the Flask app locally.

3. Build a local Docker image with the tag jwt-api-test.

4. Run the image locally, using the Gunicorn server.

5. You can pass the name of the env file using the flag --env-file=<YOUR_ENV_FILENAME>.
   You should expose the port 8080 of the container to the port 80 on your host machine.
   To use the endpoints, you can use the same curl commands as before, except using port 80 this time:

6. To try the /auth endpoint, use the following command:
```
export TOKEN=`curl -d '{"email":"<EMAIL>","password":"<PASSWORD>"}' -H "Content-Type: application/json" -X POST localhost:80/auth  | jq -r '.token'`
To try the /contents endpoint which decrypts the token and returns its content, run:
curl --request GET 'http://127.0.0.1:80/contents' -H "Authorization: Bearer ${TOKEN}" | jq .

```
### To Create EKS Cluster & Pipeline
1. Make sure they are in same region and created by same user
   ```
   eksctl create cluster --name simple-jwt-api
   ```
2. Create an IAM role that CodeBuild can use to interact with EKS. :
   2.1 Set an environment variable ACCOUNT_ID to the value of your AWS account id. You can do this with awscli:
   ```
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   ```
   2.2 Create a role policy document that allows the actions "eks:Describe*" and "ssm:GetParameters". You can do this by setting an environment variable with the role policy:
  ```
  TRUST="{ \"Version\": \"2012-10-17\", \"Statement\": [ { \"Effect\": \"Allow\", \"Principal\": { \"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:root\" }, \"Action\": \"sts:AssumeRole\" } ] }"
  ```
  2.3 Create a role named 'UdacityFlaskDeployCBKubectlRole' using the role policy document:
  ```
  aws iam create-role --role-name UdacityFlaskDeployCBKubectlRole --assume-role-policy-document "$TRUST" --output text --query 'Role.Arn'
  ```
  2.4 Create a role policy document that also allows the actions "eks:Describe*" and "ssm:GetParameters". You can create the document in your  directory:
  ```
  echo '{ "Version": "2012-10-17", "Statement": [ { "Effect": "Allow", "Action": [ "eks:Describe*", "ssm:GetParameters" ], "Resource": "*" } ] }' > iam-role-policy 
  ```
 2.5 Attach the policy to the 'UdacityFlaskDeployCBKubectlRole'. You can do this using awscli:
 ```
 aws iam put-role-policy --role-name UdacityFlaskDeployCBKubectlRole --policy-name eks-describe --policy-document file://iam-role-policy
 ```
 2.6 You have now created a role named 'UdacityFlaskDeployCBKubectlRole'
 Grant the role access to the cluster. The 'aws-auth ConfigMap' is used to grant role based access control to your cluster.

 Get the current configmap and save it to a file:
 ```
 kubectl get -n kube-system configmap/aws-auth -o yaml > /tmp/aws-auth-patch.yml
 ```
 In the data/mapRoles section of this document add, replacing <ACCOUNT_ID> with your account id:
 ```
 - rolearn: arn:aws:iam::<ACCOUNT_ID>:role/UdacityFlaskDeployCBKubectlRole
   username: build
   groups:
     - system:masters
 ```
 At end it should look like this:
 ```
    apiVersion: v1
    data:
    mapRoles: |
    - rolearn: arn:aws:iam::343090658568:role/eksctl-simple-jwt-api-nodegroup-n-NodeInstanceRole-1981JHZCXT1II
      username: system:node:{{EC2PrivateDNSName}}
      groups:
      - system:bootstrappers
      - system:nodes
    - rolearn: arn:aws:iam::343090658568:role/UdacityFlaskDeployCBKubectlRole
      username: build
      groups:
      - system:masters
    mapUsers: |
    []
    kind: ConfigMap
    metadata:
    creationTimestamp: "2020-05-24T09:58:54Z"
    name: aws-auth
    namespace: kube-system
    resourceVersion: "982"
    selfLink: /api/v1/namespaces/kube-system/configmaps/aws-auth
    uid: 310c8562-aca3-45b0-8021-2d1e3db8907c


 ```
 2.7 Now update your cluster's configmap:
 ```
 kubectl patch configmap/aws-auth -n kube-system --patch "$(cat aws-auth-patch.yml)"
 ```

3. Create the Pipeline
   3.1 Generate a GitHub access token. A Github acces token will allow CodePipeline to monitor when a repo is changed. A token can be generated here. You should generate the token with full control of private repositories, as shown in the image below. Be sure to save the token somewhere that is secure.
   3.2 The file buildspec.yml instructs CodeBuild. We need a way to pass your jwt secret to the app in kubernetes securly. You will be using AWS Parameter Store to do this. First add the following to your buildspec.yml file:
   ```
   env:
     parameter-store:         
        JWT_SECRET: JWT_SECRET
   ```
   3.3 This lets CodeBuild know to set an evironment variable based on a value in the parameter-store.
        Put secret into AWS Parameter Store
   ```
   aws ssm put-parameter --name JWT_SECRET --value "YourJWTSecret" --type SecureString
   ```
   3.4 Modify CloudFormation template.
   There is file named ci-cd-codepipeline.cfn.yml, this the the template file you will use to create your CodePipeline pipeline. Open this file and go to the 'Parameters' section. These are parameters that will accept values when you create a stack. Fill in the 'Default' value for the following:
    ```
    EksClusterName : use the name of the EKS cluster you created above
    GitSourceRepo : use the name of your project's github repo.
    GitHubUser : use your github user name
    KubectlRoleName : use the name of the role you created for kubectl above
    ```
    Save this file.
    
   3.5 Create a stack for CodePipeline.
   Go the the CloudFormation service in the aws console.
   Press the 'Create Stack' button.
   Choose the 'Upload template to S3' option and upload the template file 'ci-cd-codepipeline.cfn.yml'
   Press 'Next'. Give the stack a name, fill in your GitHub login and the Github access token generated in step 1.
   Confirm the cluster name matches your cluster, the 'kubectl IAM role' matches the role you created above, and the repository matches the name of your forked repo.
   Create the stack.
   You can check it's status in the CloudFormation console.
   Check the pipeline works. Once the stack is successfully created, commit a change to the master branch of your github repo. Then, in the aws console go to the CodePipeline UI. You should see that the build is running.
       
   3.6 To test your api endpoints, get the external ip for your service:
   ```
   kubectl get services simple-jwt-api -o wide
   ```
   3.7 Now use the external ip url to test the app:
   ```
   export TOKEN=`curl -d '{"email":"<EMAIL>","password":"<PASSWORD>"}' -H "Content-Type: application/json" -X POST <EXTERNAL-IP URL>/auth  | jq -r '.token'`
   curl --request GET '<EXTERNAL-IP URL>/contents' -H "Authorization: Bearer ${TOKEN}" | jq 
   ```

      
