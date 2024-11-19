import telegram

bot = telegram.Bot(token='TOKEN')  # Replace with your actual token

updates = bot.getUpdates()
chat_id = updates[-1].message.chat_id

print(f"Your Chat ID: {chat_id}")

message = "TESTING"
bot.send_message(chat_id=chat_id, text=message)  # Replace with your chat ID
