import datetime, subprocess, os, sys, telegram
from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

def time_for_alive_message():
  """
  Checks the current time and prints a message if it's between 17:00 and 17:10.
  """
  now = datetime.datetime.now()
  start_time = now.replace(hour=16, minute=0, second=0, microsecond=0)
  end_time = now.replace(hour=16, minute=10, second=0, microsecond=0)

  if start_time <= now <= end_time:
      return True

  start_time2 = now.replace(hour=11, minute=30, second=0, microsecond=0)
  end_time2 = now.replace(hour=11, minute=40, second=0, microsecond=0)
  if start_time2 <= now <= end_time2:
      return True

  return False

# Read credentials from a file
def read_credentials(filename):
  """Reads confidential information from a file in the same directory as the parser.py.
  That file must have four lines with username, password, telegram_bot_token, telegram_chat_id

  Args:
    filename: The name of the file containing the credentials.

  Returns:
    A tuple containing the username, password, telegram_token, telegram_chat_ID
  """
  file_path = os.path.dirname(os.path.abspath(__file__))
  path = file_path + "/" + filename
  with open(path, "r") as f:
    username = f.readline().strip()
    password = f.readline().strip()
    telegram_token = f.readline().strip()
    telegram_chat_id = f.readline().strip()
  return username, password, telegram_token, telegram_chat_id


def send_telegram(token, chat_id, message):
    """ Sends a message to a Telegram chat."""

    bot = telegram.Bot(token=token)
    bot.send_message(chat_id=chat_id, text=message)

def get_opportunity_details(driver):
    """
    Fetches details for each investment opportunity on the page.

    Args:
      driver: The Selenium webdriver instance.

    Returns:
      A list of dictionaries, where each dictionary contains details 
      for a single opportunity.
    """

    opportunities = []
    cards = WebDriverWait(driver, 15).until(
        EC.presence_of_all_elements_located((By.XPATH, "//div[@class='card card-myinvestor-sombra margin-top-15']"))
    )
    
    for card in cards:
        opportunity = {}

        # 1 - Check for "Operación asegurada"
        try:
            card.find_element(By.XPATH, ".//span[contains(text(), 'Operación asegurada')]")
            opportunity["operacion_asegurada"] = True
        except:
            opportunity["operacion_asegurada"] = False

        # 2 - Fetch "Plazo"
        try:
            plazo_element = card.find_element(By.XPATH, ".//div[contains(., 'Plazo')]/following-sibling::div")
            opportunity["plazo"] = plazo_element.text  # Example: "71 días"
        except:
            opportunity["plazo"] = None

        # 3 - Fetch "Tipo interés neto"
        try:
            interes_element = card.find_element(By.XPATH, ".//div[contains(., 'Tipo interés neto')]/following-sibling::div")
            opportunity["tipo_interes_neto"] = interes_element.text.split()[0]  # Extract "5,60 %" and then split to get "5,60"
        except:
            opportunity["tipo_interes_neto"] = None

        try:
            conseguidos_element = card.find_element(By.XPATH, ".//div[contains(., 'Conseguidos')]/following-sibling::div")
            print(conseguidos_element.text)
            conseguidos_text = conseguidos_element.text  # Example: "602,44 € (14,00 %)"
            percentage = float(conseguidos_text.split("(")[-1].split("%")[0].replace(",", "."))  # Extract percentage and convert to float
            print(percentage)
            opportunity["conseguidos"] = conseguidos_text
            opportunity["conseguidos_percentage"] = percentage
        except:
            opportunity["conseguidos"] = None
            opportunity["conseguidos_percentage"] = None

        opportunities.append(opportunity)

    return opportunities


def pretty_telegram(opportunity):
    if not opportunity["operacion_asegurada"]:
        send_telegram(token, chat_id, "Operación no asegurada")
        return
    message = "Operación asegurada\n \
    Plazo: " + opportunity["plazo"] + "\n \
    Tipo interés neto: " + opportunity["tipo_interes_neto"] + "\n \
    Porcentaje conseguidos: " + str(opportunity["conseguidos_percentage"]) + "\n"
    send_telegram(token, chat_id, message)


print("Starting")

# Get credentials
username, password, token, chat_id = read_credentials("credentials.txt")

# Set up Chrome options
chrome_options = Options()
chrome_options.add_argument("--headless")

# Set up the browser driver (replace with the path to your driver)
driver = webdriver.Chrome(options=chrome_options, executable_path="/usr/bin/chromedriver")

# Navigate to the website
driver.get("https://app.myinvestor.es/?data_traffic_origin=Web_Home#sego-projects:INVESTMENTS")

# Find the username and password fields and fill them in
username_field = WebDriverWait(driver, 10).until(
    EC.presence_of_element_located((By.XPATH, "//input[@placeholder='DNI/NIE/Pasaporte']"))
)
username_field.send_keys(username)

password_field = driver.find_element(By.XPATH, "//input[@placeholder='Contraseña']")
password_field.send_keys(password)

# Find the login button and click it
login_button = driver.find_element(By.XPATH, "//button[contains(text(), 'Verificar y entrar')]")
login_button.click()

try:
    # Wait for an element that indicates successful login (e.g., a welcome message)
    WebDriverWait(driver, 20).until(EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'SEGO Factoring')]")))  # Adjust the XPath as needed
    print("Login successful!")

except:
    print("Login failed.")
    send_telegram(token, chat_id, "Error. Login failed")
    sys.exit(-1)

try:
    # Check if the "no opportunities" message exists
    no_opportunities_message = WebDriverWait(driver, 15).until(
        EC.presence_of_element_located((By.XPATH, "//span[contains(text(), 'En este momento no hay oportunidades disponibles')]"))
    )
    print("No new opportunities available.")
    if time_for_alive_message():
        send_telegram(token, chat_id, "Sigo vivo co. No hay nuevas oportunidades")

except:
    # If the message is not found, notify using Linux notification
    print("New opportunities found! Sending notification...")
    driver.save_screenshot("screenshot.png")
    #subprocess.run(["notify-send", "New", "Item"])
    #send_telegram(token, chat_id, "Nuevas oportunidades disponibles")
    opportunities = get_opportunity_details(driver)
    send_telegram(token, chat_id, str(len(opportunities)) + " nuevas oportunidades disponibles")
    for opportunity in opportunities:
        pretty_telegram(opportunity)

# Close the browser (optional, you might want to keep it open for further actions)
driver.quit()
