import random

# Messages
messages = []
messages.append("'I think the internet is going to be one of the major forces for reducing the role of government. The one thing that's missing but that will soon be developed, is a reliable e-cash.' - Milton Friedman")
messages.append("'The swarm is headed towards us' - Satoshi Nakamoto")
messages.append("'Bitcoin seems to be a very promising idea. I like the idea of basing security on the assumption that the CPU power of honest participants outweighs that of the attacker. It is a very modern notion that exploits the power of the long tail.' - Hal Finney")
messages.append("'Bitcoin enables certain uses that are very unique. I think it offers possibilities that no other currency allows. For example the ability to spend a coin that only occurs when two separate parties agree to spend the coin; with a third party that couldn't run away with the coin itself.' - Pieter Wuille")
messages.append("'Hey, obviously this is a very interesting time to be in Bitcoin right now, but if you guys want to argue over whether this is reality or not, one Bitcoin will feed over 40 homeless people in Pensacola right now. If you guys want proof Bitcoin is real, send them to me, I'll cash them out and feed homeless people.' - Jason King")
messages.append("'Bitcoin was created to serve a highly political intent, a free and uncensored network where all can participate with equal access.' - Amir Taaki")
messages.append("'When I first heard about Bitcoin, I thought it was impossible. How can you have a purely digital currency? Can't I just copy your hard drive and have your bitcoins? I didn't understand how that could be done, and then I looked into it and it was brilliant' - Jeff Garzik")
messages.append("'The bitcoin world is this new ecosystem where it doesn't cost that much to start a new bitcoin company, it doesn't cost much to start owning bitcoin either, and it is a much more efficient way of moving money around the world.' - Tim Draper")
messages.append("'Cryptocurrency is such a powerful concept that it can almost overturn governments' - Charlie Lee")
messages.append("'Bitcoin is a remarkable cryptographic achievement and the ability to create something that is not duplicable in the digital world has enormous value' - Eric Schmidt, CEO of Google")
messages.append("'Bitcoin is a technological tour de force.' - Bill Gates")
messages.append("'Lost coins only make everyone else's coins worth slightly more.  Think of it as a donation to everyone.' - Satoshi Nakamoto")
messages.append("'The Times 03/Jan/2009 Chancellor on brink of second bailout for banks.' - Satoshi Nakamoto")
messages.append("'Your keys. Your bitcoin. Not your keys. Not your bitcoin!' - Andreas Antonopoulos")
messages.append("'Running bitcoin' - Hal Finney @ 9:33 PM 10 Jan 2009")
messages.append("'Since we're all rich with bitcoins, or we will be once they're worth a million dollars like everyone expects, we ought to put some of this unearned wealth to good use.' - Hal Finney")
messages.append("'I see Bitcoin as ultimately becoming a reserve currency for banks, playing much the same role as gold did in the early days of banking. Banks could issue digital cash with greater anonymity and lighter weight, more efficient transactions.' - Hal Finney")
messages.append("'Bitcoin actually has the balance and incentives center, and that is why it is starting to take off.' - Julian Assange")
messages.append("'Bitcoin may be the TCP/IP of money.' - Paul Buchheit")
messages.append("'I understand the political ramifications of [bitcoin] and I think that the government should stay out of them and they should be perfectly legal.' - Ron Paul")
messages.append("'The reason we are all here is that the current financial system is outdated.' - Charlie Shrem")
messages.append("'At the end of the day, Bitcoin is programmable money.' - Andreas Antonopoulos")

# Funny messages
funny_messages = []
funny_messages.append("I think I can. I think I can. I think I can.")
funny_messages.append("Almost there! Stay on target!")
funny_messages.append("Blockchains get big! Imagine if we had 64 MB blocks...")


### Helper functions
def get_message(include_funny=True):
    possible_messages = messages
    if include_funny:
        possible_messages = messages + funny_messages

    msg = random.choice(possible_messages)
    return msg