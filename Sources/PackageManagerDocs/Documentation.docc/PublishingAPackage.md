# Publishing a Swift package

<!--@START_MENU_TOKEN@-->Summary<!--@END_MENU_TOKEN@-->

## Overview

To publish a package, create and push a semantic version tag:

    $ git init
    $ git add .
    $ git remote add origin [github-URL]
    $ git commit -m "Initial Commit"
    $ git tag 1.0.0
    $ git push origin master --tags

Now other packages can depend on version 1.0.0 of this package using the github
url.
An example of a published package can be found here:
https://github.com/apple/example-package-fisheryates
