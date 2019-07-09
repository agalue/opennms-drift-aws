# @author: Alejandro Galue <agalue@opennms.org>

############################ IMPORTANT ############################
#
# Make sure you put your AWS credentials on ~/.aws/credentials
# prior start using this recipe.
#
###################################################################

provider "aws" {
  region = var.aws_region
}

