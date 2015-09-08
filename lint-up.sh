# Because we want a failure here to fail the entire job, we have to run this script in the 'script' stage.
# http://docs.travis-ci.com/user/customizing-the-build/#Breaking-the-Build


# ==== SETUP ====

# User name for git commits made by this script.
TRAVS_GIT_USERNAME="Travis CI server"

# File name and relative path of generated Lint report. Must match build.gradle file:
#   lintOptions {
#       htmlOutput file("[FILE_NAME].html")
#   }
LINT_REPORT_FILE="Receipts/lint-report.html"

# File name and relative path of previous results of this script.
PREVIOUS_LINT_RESULTS_FILE="lint-report/lint-results.xml"

# Flag to evaluate warnings. true = check warnings; false = ignore warnings
CHECK_WARNINGS=true

# ==== SETUP DONE; DON'T TOUCH ANYTHING BELOW  ====

echo "======= starting Lint script ========"

# TODO this isn't working
## only run this script if this is a pull request, not a master merge
#if [[ "$TRAVIS_PULL_REQUEST" = "false" ]];
#then
#  echo "This is a NOT pull request. "
#  exit 0 # success
#fi

echo "running Lint..."
./gradlew clean lint

if [ ! -f "$LINT_REPORT_FILE" ]
then
    echo "Lint HTML report not found."
    exit 1 # fail
fi

CURRENT_ERROR_COUNT=0
CURRENT_WARNING_COUNT=0

# find string in html report
# [0-9][0-9]* will match ONE OR MORE digit; we want to ensure we have at least one digit
# in other words, we do NOT want to match the string "some errors and warnings"
ERROR_WARNING_STRING=$(grep '[0-9][0-9]* errors and [0-9][0-9]* warnings' $LINT_REPORT_FILE)

# find number of errors in string
CURRENT_ERROR_COUNT=$(echo $ERROR_WARNING_STRING | sed -E 's/([0-9]) errors.*/\1/')
echo "found errors: ${CURRENT_ERROR_COUNT}"

# find number of warnings in string
if [ "$CHECK_WARNINGS" = true ]
then
    CURRENT_WARNING_COUNT=$(echo $ERROR_WARNING_STRING | sed -E 's/.* ([0-9]+) warnings.*/\1/')
    echo "found warnings: ${CURRENT_WARNING_COUNT}"
fi

# get previous error and warning counts from last successful build
PREVIOUS_ERROR_COUNT=0
PREVIOUS_WARNING_COUNT=0
if [ -f "$PREVIOUS_LINT_RESULTS_FILE" ]
then
    PREVIOUS_ERROR_WARNING_STRING=$(grep '[0-9][0-9]* errors and [0-9][0-9]* warnings' $PREVIOUS_LINT_RESULTS_FILE)
    PREVIOUS_ERROR_COUNT=$(echo $PREVIOUS_ERROR_WARNING_STRING | sed -E 's/([0-9]) errors.*/\1/')
    echo "previous errors: ${PREVIOUS_ERROR_COUNT}"

    if [ "$CHECK_WARNINGS" = true ]
    then
        PREVIOUS_WARNING_COUNT=$(echo $PREVIOUS_ERROR_WARNING_STRING | sed -E 's/.* ([0-9]+) warnings.*/\1/')
        echo "previous warnings: ${PREVIOUS_WARNING_COUNT}"
    fi

else
    echo "Previous Lint result file not found."
fi

# compare previous count with current count
if [ "$CURRENT_ERROR_COUNT" -gt "$PREVIOUS_ERROR_COUNT" ]
then
    echo "FAIL: error count increased"
    exit 1 # failure
fi

if [ "$CHECK_WARNINGS" = true ]
then
    if [ "$CURRENT_WARNING_COUNT" -gt "$PREVIOUS_WARNING_COUNT" ]
    then
        echo "FAIL: warning count increased"
        exit 1 # failure
    fi
fi

if [ "$CURRENT_ERROR_COUNT" -eq "$PREVIOUS_ERROR_COUNT" ] &&
   [ "$CURRENT_WARNING_COUNT" -eq "$PREVIOUS_WARNING_COUNT" ]
then
    echo "SUCCESS: count stayed the same"
    exit 0 # success
fi

# either error count or warning count DECREASED
# update previous results with current results
rm "$PREVIOUS_LINT_RESULTS_FILE"
echo "DO NOT TOUCH; GENERATED BY TRAVIS" >> "$PREVIOUS_LINT_RESULTS_FILE"
echo "$ERROR_WARNING_STRING" >> "$PREVIOUS_LINT_RESULTS_FILE"

# if this script is run locally, we don't want to overwrite git username and email, so save temporarily
PREVIOUS_GIT_USERNAME=$(git config --global user.name)
git config --global user.name "$TRAVS_GIT_USERNAME"

git add "$PREVIOUS_LINT_RESULTS_FILE"

# Travis has git in a detached head here. Let's get on the right branch.
git checkout "$TRAVIS_BRANCH"

# commit changes; Add "skip ci" so that we don't accidentally trigger another Travis build
git commit -m "Travis: update Lint results to reflect reduced error/warning count [skip ci]"

# push to origin
git config push.default simple
git push
echo "changes pushed to origin"

# restore previous git user name
git config --global user.name "$PREVIOUS_GIT_USERNAME"

echo "SUCCESS: count was reduced"

exit 0 # success